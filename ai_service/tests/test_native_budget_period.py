from pydantic import create_model,ValidationError
from typing import Literal
import pytest
from app.domain.entities.intent_decision import NativeBudgetPeriod,NativeRequestUnderstanding,NativePlanningUnderstanding,NativeKnownFact
from app.infrastructure.llm.provider_client import native_schema


def test_native_number_fact_preserves_domain_string_without_punctuation_placeholder():
    fact=NativeKnownFact.model_validate({'dimension':'budget_max','value':500,'source_message_ids':['answers']})
    assert fact.value=='500'
    spec=native_schema(NativeKnownFact)['properties']['value']
    assert {branch['type'] for branch in spec['anyOf']}=={'string','number'}


def test_native_period_schema_constrains_catalog_units_and_preserves_unsupported_user_period():
    period=create_model('FixtureCatalogPeriod',__base__=NativeBudgetPeriod,
        catalog_unit=(Literal['วัน','เดือน']|None,NativeBudgetPeriod.model_fields['catalog_unit']))
    spec=native_schema(period)['properties']['catalog_unit']
    assert spec['anyOf'][0]['enum']==['วัน','เดือน']
    with pytest.raises(ValidationError):period(user_period='ต่อวัน',catalog_unit='day')
    known=period(user_period='ต่อวัน',catalog_unit='วัน')
    assert known.catalog_unit=='วัน'
    unsupported=period(user_period='ต่อสัปดาห์',catalog_unit=None)
    assert unsupported.user_period=='ต่อสัปดาห์' and unsupported.catalog_unit is None
    # native contract emits explicit period resolution; domain DTOs keep their string unit.
    understanding=native_schema(NativeRequestUnderstanding)
    assert 'budget_period' in understanding['required']
    assert 'budget_unit' not in understanding['properties']


def test_groq_instruction_uses_catalog_period_literals_from_the_actual_native_schema():
    from app.infrastructure.llm.groq_client import GroqClient
    from app.domain.entities.turn_plan import NativeTurnPlan
    period=create_model('FixtureCatalogPeriod',__base__=NativeBudgetPeriod,
        catalog_unit=(Literal['วัน','เดือน']|None,NativeBudgetPeriod.model_fields['catalog_unit']))
    analysis=create_model('FixtureAnalysis',__base__=NativePlanningUnderstanding,
        budget_unit=(period|None,NativePlanningUnderstanding.model_fields['budget_unit']))
    plan=create_model('FixturePlan',__base__=NativeTurnPlan,
        understanding=(analysis,NativeTurnPlan.model_fields['understanding']))
    client=GroqClient(api_key='fixture')
    model=client.runtime.providers[-1].proposed_model
    payload=client.build_payload(model,'fixture request',schema=plan)
    assert payload['response_format']['json_schema']['strict'] is True
    assert '"analysis.budget_period.catalog_unit":["วัน","เดือน"]' in payload['messages'][0]['content']
    assert '"catalog_unit":"day"' not in payload['messages'][0]['content']
    assert '"stage.catalog_operation.kind":["none","selection","inspection","comparison"]' in payload['messages'][0]['content']
