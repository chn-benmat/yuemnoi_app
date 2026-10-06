import json
from types import SimpleNamespace
from pydantic import ValidationError
import pytest
from evaluation.role_probes import replay_schema
from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.catalog_guidance import compact_catalog, catalog_snapshot
from app.domain.entities.turn_plan import EvidenceAnswer
from test_fast_turn import ITEM, make_fast, turn, equipment_answer
from test_request_understanding import understanding


def test_probe_replay_keeps_native_null_budget_and_runtime_reference_validation():
    fast,_,_,_=make_fast(turn())
    decision=understanding(catalog_operation='inspection',budget_max=None,budget_unit=None)
    payload={'understanding':decision.model_dump(),'catalog':compact_catalog(catalog_snapshot([ITEM])),
        'selection_required':True,'allowed_search_ids':[], 'allowed_selection_purposes':['inspection'],
        'price_contract':{'ceiling':None,'permitted_catalog_periods':[]}}
    record={'phase':'evidence','prompt':json.dumps(payload),'schema':EvidenceAnswer.model_json_schema()}
    container=SimpleNamespace(query_items_use_case=fast._query)
    schema=replay_schema(record,ChatRequestDTO(message='fixture'),container,None,[ITEM])
    data=equipment_answer(purpose='inspection').model_dump()
    assert schema.model_validate(data).request_fit=='not_assessed'
    data['selection']['price_requirement']={'maximum':100,'user_unit':'วัน','catalog_units':['วัน']}
    with pytest.raises(ValidationError):
        schema.model_validate(data)


def test_probe_review_cannot_accept_a_fabricated_span():
    record={'phase':'review','prompt':json.dumps({'draft':{'response':'actual draft'}}),
            'schema':{'title':'FixtureReview'}}
    schema=replay_schema(record,ChatRequestDTO(message='fixture'),None,None,[])
    with pytest.raises(ValidationError):
        schema.model_validate({'semantic_pass':True,'neutral_voice_pass':False,'issues':[
            {'kind':'neutral_voice','field_path':'/response','quoted_text':'fabricated','reason':'fixture'}]})
