import json
from pathlib import Path
from pydantic import BaseModel
from app.core.config import settings
from app.infrastructure.llm.groq_client import GroqClient
from native_turn_fixture import current_capture_schema


def test_actual_completed_native_questionnaire_fits_without_raising_provider_capacity():
    source = json.loads((Path(__file__).parent / 'fixtures/native_completed_questionnaire_planning.json').read_text(encoding='utf-8'))
    document = current_capture_schema(source['schema'])
    model = type(document['title'], (BaseModel,), {'model_json_schema': staticmethod(lambda: document)})
    policy = json.loads(settings.INTERPRETATION_POLICY_PATH.read_text(encoding='utf-8'))
    client = GroqClient(api_key='fixture')
    for profile in client.runtime.providers:
        if profile.enabled and profile.protocol == client.protocol:
            cost = client.request_cost('generate_structured', getattr(settings, profile.model_setting),
                dict(prompt=source['prompt'], schema=model, system_instruction=policy['turn_instruction']))
            assert cost <= profile.quota.tokens_per_window
