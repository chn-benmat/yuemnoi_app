import json
from app.infrastructure.llm.provider_client import ProviderClient, native_schema, compact_schema_definitions
from app.infrastructure.llm.reference_transport import encode_references,decode_references


class GroqClient(ProviderClient):
    protocol = "groq_json_schema"
    provider = "groq"
    key_setting = "GROQ_API_KEY"

    def url(self, model):
        return str(self.profile(model).endpoint)

    def headers(self):
        return {"Authorization": f"Bearer {self._api_key}"}

    def build_payload(self, model, prompt, system_instruction=None, temperature=None, schema=None, max_tokens=None):
        messages = []
        if schema is not None:
            document = native_schema(schema)
            prompt,document,_ = encode_references(prompt,document)
            document = compact_schema_definitions(document)
            contract = ('Return JSON with required root keys: '
                + ','.join(document['required'])
                + '. Exact enum labels and required nested keys; no extras. Missing facts: []; null only where allowed.')
            # อ่านทั้ง object, array และ union เพื่อให้โมเดลเห็นสัญญาของคำถามแต่ละข้อ
            # เก็บทางเลือกแยกกัน ไม่รวม keys ของคนละชนิดจนเกิด object ที่ผิด schema
            definitions = document.get('$defs', {})
            objects, nested_literals, meanings = {}, {}, {}
            def visit_object(spec, path, ancestors):
                description = spec.get('description')
                if description:
                    descriptions = meanings.setdefault(path, [])
                    if description not in descriptions:
                        descriptions.append(description)
                reference = spec.get('$ref')
                if reference:
                    if reference in ancestors:
                        return
                    visit_object(definitions.get(reference.removeprefix('#/$defs/'), {}),
                                 path, ancestors | {reference})
                    return
                if path and spec.get('type') == 'object':
                    alternatives = objects.setdefault(path, [])
                    required = spec.get('required', [])
                    if required not in alternatives:
                        alternatives.append(required)
                # root arrays เป็นรายการหลักฐานที่อนุญาต ไม่ใช่รายการที่ต้องเลือกทั้งหมด
                if '.' in path and not path.endswith('[]') and 'enum' in spec:
                    literals = nested_literals.setdefault(path, [])
                    for value in spec['enum']:
                        if value not in literals:
                            literals.append(value)
                for branch in spec.get('anyOf', []):
                    visit_object(branch, path, ancestors)
                if 'items' in spec:
                    visit_object(spec['items'], path + '[]', ancestors)
                for name, child in spec.get('properties', {}).items():
                    child_path = path + '.' + name if path else name
                    visit_object(child, child_path, ancestors)
            visit_object(document, '', set())
            # สรุป object ชั้นแรก แบบฟอร์มใน array และ union ที่มี keys ต่างกัน
            # รายละเอียดอื่นยังอยู่ใน native schema เพื่อลดการส่งสัญญาเดิมซ้ำ
            objects = {path: alternatives for path, alternatives in objects.items()
                       if '.' not in path or path.count('[]') == 1 or len(alternatives) > 1}
            shared_meanings, moved_descriptions = {}, set()
            for path, descriptions in meanings.items():
                if '[]' not in path and path + '[]' not in objects and len(objects.get(path, [])) <= 1:
                    continue
                unique = [description for description in descriptions if description not in moved_descriptions]
                if unique:
                    shared_meanings[path] = unique
                    moved_descriptions.update(unique)
            # ย้ายคำอธิบายไปให้โมเดลอ่านครั้งเดียว โดยคงทุก constraint ใน native schema
            def move_meanings(value):
                if isinstance(value, list):
                    return [move_meanings(child) for child in value]
                if isinstance(value, dict):
                    return {key: move_meanings(child) for key, child in value.items()
                            if key != 'description' or child not in moved_descriptions}
                return value
            document = move_meanings(document)
            contract += ' Nested keys: ' + json.dumps(objects,ensure_ascii=False,separators=(',',':')) + '.'
            if nested_literals:
                contract += ' Nested literals: ' + json.dumps(nested_literals,ensure_ascii=False,separators=(',',':')) + '.'
            if shared_meanings:
                contract += ' Nested meanings: ' + json.dumps(shared_meanings,ensure_ascii=False,separators=(',',':')) + '.'
                contract += ' Shared field meanings apply in every branch.'
            system_instruction = (system_instruction + '\n' if system_instruction else '') + contract
        if system_instruction:
            messages.append({"role": "system", "content": system_instruction})
        messages.append({"role": "user", "content": prompt})
        payload = {"model": model, "messages": messages, "temperature": self.configuration.GUIDANCE_TEMPERATURE if temperature is None else temperature,
                   "max_completion_tokens": self.configuration.STRUCTURED_MAX_OUTPUT_TOKENS if max_tokens is None else max_tokens}
        effort = self.profile(model).reasoning_effort
        if effort is not None:
            payload["reasoning_effort"] = effort
        if schema is not None:
            payload["response_format"] = {"type": "json_schema", "json_schema": {
                "name": schema.__name__, "strict": True, "schema": document}}
        return payload

    def decode_candidate(self, candidate, prompt, schema):
        _,_,aliases = encode_references(prompt,native_schema(schema))
        return decode_references(candidate,aliases)

    @staticmethod
    def structured_completion_error(data: dict) -> str | None:
        choice = data["choices"][0]
        message = choice["message"]
        if message.get("refusal") is not None:
            return "structured_output_refused"
        if choice.get("finish_reason") == "length":
            return "structured_output_truncated"
        if choice.get("finish_reason") != "stop" or message.get("tool_calls") or message.get("function_call"):
            return "structured_output_incomplete"
        return None

    @staticmethod
    def content(data):
        content = data["choices"][0]["message"]["content"]
        if not isinstance(content, str):
            raise ValueError("Missing text")
        return content

    @staticmethod
    def usage(data):
        raw = data.get("usage") or {}
        usage = {k: raw[k] for k in ("prompt_tokens", "completion_tokens", "total_tokens") if isinstance(raw.get(k), int)}
        details = raw.get("prompt_tokens_details") or {}
        if isinstance(details.get("cached_tokens"), int):
            usage["cached_tokens"] = details["cached_tokens"]
        return usage
