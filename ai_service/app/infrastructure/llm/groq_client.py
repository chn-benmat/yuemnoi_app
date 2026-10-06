from app.infrastructure.llm.provider_client import ProviderClient, native_schema


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
                "name": schema.__name__, "strict": True, "schema": native_schema(schema)}}
        return payload

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
