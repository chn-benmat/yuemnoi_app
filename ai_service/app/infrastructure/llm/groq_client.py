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
            contract = ('Emit one JSON object with every required root key: '
                + ', '.join(document['required'])
                + '. Complete nested fields, use exact enum labels and no extra keys. Absent facts use []; null only where allowed.')
            # Required nested labels remain explicit even when the provider's
            # JSON generation fails to follow a referenced schema definition.
            definitions=document.get('$defs',{})
            objects={}
            for name,property_schema in document['properties'].items():
                branches=property_schema.get('anyOf',[property_schema])
                labels=[]
                for branch in branches:
                    definition=definitions.get(branch.get('$ref','').removeprefix('#/$defs/'),{})
                    for label in definition.get('required',[]):
                        if label not in labels:labels.append(label)
                if labels:objects[name]=labels
            contract+=' Nested keys: '+json.dumps(objects,ensure_ascii=False,separators=(',',':'))+'.'
            # Referenced nullable objects (such as an established billing
            # period) need their exact machine literals in the instruction
            # too. Keep this structural: never translate or infer user values.
            nested_literals = {}
            def visit_object(spec, path, ancestors):
                reference = spec.get('$ref')
                if reference:
                    if reference in ancestors:
                        return
                    spec = definitions.get(reference.removeprefix('#/$defs/'), {})
                    ancestors = ancestors | {reference}
                for branch in spec.get('anyOf', []):
                    visit_object(branch, path, ancestors)
                for name, child in spec.get('properties', {}).items():
                    child_path = path + '.' + name if path else name
                    if path.count('.') >= 1:
                        enums = [part['enum'] for part in child.get('anyOf', [child]) if 'enum' in part]
                        if enums:
                            literals = nested_literals.setdefault(child_path, [])
                            for values in enums:
                                for value in values:
                                    if value not in literals:
                                        literals.append(value)
                    visit_object(child, child_path, ancestors)
            visit_object(document, '', set())
            if nested_literals:
                contract += ' Nested literals: ' + json.dumps(nested_literals,ensure_ascii=False,separators=(',',':')) + '.'
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
