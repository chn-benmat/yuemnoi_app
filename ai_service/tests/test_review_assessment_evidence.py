"""A boolean approval must not stand in for independently grounded assessments."""
import pytest
from pydantic import ValidationError
from app.application.dtos.chat_dto import ChatRequestDTO,ChatResponseDTO
from app.domain.interfaces.generation_stage import Provenance
from test_response_review import stack


@pytest.mark.asyncio
async def test_boolean_only_false_acceptance_is_not_an_admissible_review():
    # The actual R1 reviewer returned these approvals despite its assistant voice.
    review,_=stack(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],
        checks={k:True for k in ('relevance','completeness','neutral_voice','choice_equivalence','grounding','context','followups')},
        reviewed_surface_groups=['response']),assessments=False)
    with pytest.raises(ValidationError):
        await review.execute(ChatRequestDTO(message='ขอราคา Canon EOS R50'),
            ChatResponseDTO(response='ราคา 650 บาทต่อวันครับ'),[Provenance('fixture','writer')],[],[],[])


@pytest.mark.asyncio
async def test_assessment_cannot_cite_request_or_invented_draft_paths():
    from review_fixture import assessed
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],
        reviewed_surface_groups=['response']),paths=['/draft/response'])
    review,_=stack(value,assessments=False)
    with pytest.raises(ValidationError,match='review_unknown_assessment_path'):
        await review.execute(ChatRequestDTO(message='fixture'),ChatResponseDTO(response='actual draft'),
            [Provenance('fixture','writer')],[],[],[])


def test_native_schema_orders_assessments_before_final_verdict():
    from app.domain.entities.response_review import NativeResponseReview
    schema=NativeResponseReview.model_json_schema()
    assert list(schema['properties'])[0]=='assessments'
    assert 'assessments' in schema['required']
    assert not {'checks','semantic_pass','neutral_voice_pass'} & set(schema['properties'])


def test_duplicate_or_issues_disagreeing_assessments_are_not_native_valid():
    from app.domain.entities.response_review import NativeResponseReview
    from review_fixture import assessed
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],reviewed_surface_groups=['response']))
    value['assessments'][1]['check']='relevance'
    with pytest.raises(ValidationError,match='exactly one'):NativeResponseReview.model_validate(value)
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],reviewed_surface_groups=['response']))
    value['assessments'][0]['passed']=False
    with pytest.raises(ValidationError,match='must agree'):NativeResponseReview.model_validate(value)


def test_voice_failure_does_not_duplicate_or_change_semantic_assessment():
    from app.domain.entities.response_review import NativeResponseReview
    from review_fixture import assessed
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=False,issues=[
        {'kind':'neutral_voice','field_path':'/response','quoted_text':'ครับ','reason':'actual assistant honorific'}],
        reviewed_surface_groups=['response']))
    native=NativeResponseReview.model_validate(value)
    result=native.as_review()
    assert result.semantic_pass is True and result.neutral_voice_pass is False
    # An old inconsistent verdict is still extra invalid data, never normalized.
    with pytest.raises(ValidationError):NativeResponseReview.model_validate({**value,'semantic_pass':False})


def test_both_actual_provider_payloads_keep_review_pointer_contract():
    from app.domain.entities.response_review import NativeResponseReview
    from app.infrastructure.llm.gemini_client import GeminiClient
    from app.infrastructure.llm.groq_client import GroqClient
    from app.core.config import settings
    gemini=GeminiClient(api_key='fixture').build_payload(settings.GEMINI_PRIMARY_MODEL,'fixture',schema=NativeResponseReview)
    groq=GroqClient(api_key='fixture').build_payload(settings.GROQ_PRIMARY_MODEL,'fixture',schema=NativeResponseReview)
    schemas=[gemini['generationConfig']['responseJsonSchema'],groq['response_format']['json_schema']['schema']]
    assert schemas[0]==schemas[1]
    for schema in schemas:
        issue=schema['$defs']['ReviewIssue']['properties']
        assert 'relative to the restored draft root' in issue['field_path']['description']
        assert 'Exact unchanged substring' in issue['quoted_text']['description']
        assert list(schema['properties'])[0]=='assessments'


@pytest.mark.asyncio
async def test_assessment_can_reference_actual_empty_collection_without_inventing_text():
    from review_fixture import assessed
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],
        reviewed_surface_groups=['response']),paths=['/questions','/items','/suggested_replies'])
    review,_=stack(value,assessments=False)
    result=await review.execute(ChatRequestDTO(message='fixture'),ChatResponseDTO(response='actual draft'),
        [Provenance('fixture','writer')],[],[],[])
    assert result.semantic_pass and result.neutral_voice_pass
