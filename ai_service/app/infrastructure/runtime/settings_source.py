"""JSON is below explicit settings, environment and dotenv in precedence."""

from pathlib import Path

from pydantic_settings import PydanticBaseSettingsSource

from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import RuntimeDocument

SERVICE_ROOT = Path(__file__).resolve().parents[3]


def setting_values(document: RuntimeDocument) -> dict:
    values = {
        "APP_KNOWLEDGE_PATH": SERVICE_ROOT / document.knowledge_path,
        "INTERPRETATION_POLICY_PATH": SERVICE_ROOT / document.interpretation_policy_path,
        "AI_QUOTA_LEDGER_PATH": SERVICE_ROOT / document.quota_ledger.path,
        "INTENT_CONTEXT_MAX_MESSAGES": document.limits.messages,
        "INTENT_CONTEXT_MAX_CHARACTERS": document.limits.characters,
        "INTENT_TEMPERATURE": document.limits.temperature,
        "GUIDANCE_MAX_QUESTIONS": document.limits.questions,
        "GUIDANCE_MAX_OPTIONS": document.limits.choices_per_question,
        "GUIDANCE_MAX_ITEMS": document.limits.items,
        "GUIDANCE_TEMPERATURE": document.limits.temperature,
        "STRUCTURED_MAX_OUTPUT_TOKENS": document.limits.output_tokens,
        "GUIDANCE_TITLE_MAX_CHARACTERS": document.limits.question_title_characters,
        "GUIDANCE_OPTION_MAX_CHARACTERS": document.limits.choice_label_characters,
        "GUIDANCE_GENERATION_ATTEMPTS": document.limits.generation_attempts,
        "CHAT_STREAM_HEARTBEAT_SECONDS": document.stream.heartbeat_seconds,
        "CHAT_STREAM_CHUNK_CHARACTERS": document.stream.chunk_characters,
    }
    values.update({p.model_setting: p.proposed_model for p in document.providers})
    return values


class RuntimeSettingsSource(PydanticBaseSettingsSource):
    def get_field_value(self, field, field_name):
        return None, field_name, False

    def __call__(self):
        path = Path(self.current_state.get("AI_RUNTIME_PATH", self.settings_cls.model_fields["AI_RUNTIME_PATH"].default))
        document, _ = ValidatedFile(path, RuntimeDocument).read()
        return setting_values(document)
