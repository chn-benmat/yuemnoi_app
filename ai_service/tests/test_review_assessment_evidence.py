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
    with pytest.raises(ValidationError) as failure:
        await review.execute(ChatRequestDTO(message='fixture'),ChatResponseDTO(response='actual draft'),
            [Provenance('fixture','writer')],[],[],[])
    assert all(error['type'] == 'review_unknown_assessment_path'
               for error in failure.value.errors())


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
    value['assessments'].pop('completeness')
    with pytest.raises(ValidationError,match='completeness'):NativeResponseReview.model_validate(value)
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],reviewed_surface_groups=['response']))
    value['assessments']['relevance']['passed']=False
    with pytest.raises(ValidationError,match='must agree'):NativeResponseReview.model_validate(value)


def test_native_review_schema_requires_each_check_instead_of_counting_array_entries():
    from app.domain.entities.response_review import NativeResponseReview, ResponseChecks
    from app.infrastructure.llm.provider_client import native_schema, decode_structured
    from review_fixture import assessed
    schema=native_schema(NativeResponseReview)
    checks=schema['$defs']['NamedReviewAssessments']
    assert set(checks['required']) == (set(ResponseChecks.model_fields) - {'neutral_voice'}) | {'ungendered_speaker'}
    assert checks['additionalProperties'] is False
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],reviewed_surface_groups=['response']))
    # The failure seen live had seven entries but repeated followups and omitted
    # mandatory checks. That shape is now invalid in the native schema itself.
    rows=[{'check':'followups',**value['assessments']['followups']}] * 7
    with pytest.raises(ValidationError):NativeResponseReview.model_validate({**value,'assessments':rows})
    with pytest.raises(ValueError,match='Duplicate JSON property'):
        decode_structured('{"assessments":{"relevance":{},"relevance":{}}}',NativeResponseReview)


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


def test_all_groq_model_payloads_keep_review_pointer_contract():
    from app.domain.entities.response_review import NativeResponseReview
    from app.infrastructure.llm.groq_client import GroqClient
    from app.core.config import settings
    from app.infrastructure.llm.provider_client import compact_schema_definitions
    schemas=[GroqClient(api_key='fixture').build_payload(model,'fixture',schema=NativeResponseReview)['response_format']['json_schema']['schema'] for model in settings.groq_models]
    assert compact_schema_definitions(schemas[0]) == schemas[1]
    assert schemas[1] == schemas[2]
    for schema in schemas:
        ref = schema['properties']['issues']['items']['$ref'].removeprefix('#/$defs/')
        issue=schema['$defs'][ref]['properties']
        assert 'relative to the restored draft root' in issue['field_path']['description']
        assert 'Exact unchanged substring' in issue['quoted_text']['description']
        assert list(schema['properties'])[0]=='assessments'


@pytest.mark.asyncio
async def test_review_prompt_supplies_actual_surface_paths_without_request_paths():
    import json
    from app.application.services.response_review import VISIBLE_TEXT_SURFACES
    from app.application.services.review_input import restore_planning_input
    from review_fixture import assessed
    value = assessed(dict(semantic_pass=True, neutral_voice_pass=True, issues=[],
        reviewed_surface_groups=['response']))
    review, llm = stack(value, assessments=False)
    draft = ChatResponseDTO(response='actual draft')
    await review.execute(ChatRequestDTO(message='different request'), draft,
        [Provenance('fixture', 'writer')], [], [], [])
    payload = restore_planning_input(json.loads(llm.generate_structured.call_args.kwargs['prompt']))
    assert set(payload['assessment_field_paths']) == {'/' + name for name in VISIBLE_TEXT_SURFACES
        if name in draft.model_dump(mode='json')}
    assert '/request/message' not in payload['assessment_field_paths']


@pytest.mark.asyncio
async def test_assessment_can_reference_actual_empty_collection_without_inventing_text():
    from review_fixture import assessed
    value=assessed(dict(semantic_pass=True,neutral_voice_pass=True,issues=[],
        reviewed_surface_groups=['response']),paths=['/questions','/items','/suggested_replies'])
    review,_=stack(value,assessments=False)
    result=await review.execute(ChatRequestDTO(message='fixture'),ChatResponseDTO(response='actual draft'),
        [Provenance('fixture','writer')],[],[],[])
    assert result.semantic_pass and result.neutral_voice_pass
