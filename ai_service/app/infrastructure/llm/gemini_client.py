from app.infrastructure.llm.provider_client import ProviderClient, native_schema


class GeminiClient(ProviderClient):
    protocol = "gemini_json_schema"
    provider = "gemini"
    key_setting = "GEMINI_API_KEY"

    def url(self, model):
        return f"{str(self.profile(model).endpoint).rstrip('/')}/{model}:generateContent"

    def headers(self):
        return {"x-goog-api-key": self._api_key}

    def build_payload(self, model, prompt, system_instruction=None, temperature=None, schema=None, max_tokens=None):
        generation = {"temperature": self.configuration.GUIDANCE_TEMPERATURE if temperature is None else temperature,
                      "maxOutputTokens": self.configuration.STRUCTURED_MAX_OUTPUT_TOKENS if max_tokens is None else max_tokens}
        if schema is not None:
            generation.update(responseMimeType="application/json", responseJsonSchema=native_schema(schema))
        payload = {"contents": [{"parts": [{"text": prompt}]}], "generationConfig": generation}
        if system_instruction:
            payload["systemInstruction"] = {"parts": [{"text": system_instruction}]}
        return payload

    @staticmethod
    def content(data):
        parts = data["candidates"][0]["content"]["parts"]
        text = "".join(p.get("text", "") for p in parts if not p.get("thought", False))
        if not text:
            raise ValueError("Missing text")
        return text

    @staticmethod
    def usage(data):
        raw = data.get("usageMetadata") or {}
        mapping = {"promptTokenCount": "prompt_tokens", "candidatesTokenCount": "completion_tokens",
                   "totalTokenCount": "total_tokens", "cachedContentTokenCount": "cached_tokens"}
        return {target: raw[source] for source, target in mapping.items() if isinstance(raw.get(source), int)}
