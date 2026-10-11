"""ป้องกันเอกสารภายในปะปนกับคำแนะนำสินค้า"""
import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.review_input import restore_planning_input
from app.domain.entities.turn_plan import NativeTurnPlan, TurnPlan
from app.domain.exceptions import GuidanceGenerationError
from app.domain.interfaces.generation_stage import CURRENT_GENERATION, Provenance
from test_fast_turn import ITEM, equipment_answer, make_fast, turn
from test_request_understanding import understanding


@pytest.mark.asyncio
async def test_product_recommendation_does_not_prepend_the_entire_app_manual():
    decision = understanding(catalog_operation='selection', information_sufficient=True,
                             next_action='answer', missing_slots=[], additional_goals=[])
    case, llm, *_ = make_fast(turn(understanding=decision, knowledge_ids=[], response_mode='equipment'),
                              equipment_answer())
    knowledge = await case._knowledge.get_approved_knowledge()
    contaminated = turn(understanding=decision, response_mode='equipment',
                        knowledge_ids=[knowledge.articles[-1].id])
    llm.generate_structured.side_effect = [contaminated, equipment_answer()]
    with pytest.raises(ValidationError, match='separately requested app information'):
        await case.execute(ChatRequestDTO(message='แนะนำอุปกรณ์ตามความต้องการที่ตอบไว้'))
    assert llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_mixed_request_projects_only_approved_public_app_facts():
    decision = understanding(catalog_operation='selection', information_sufficient=True,
                             next_action='answer', missing_slots=[],
                             user_goal='สมัครสมาชิกและเลือกอุปกรณ์ถ่ายคลิป',
                             budget_max=100, budget_unit=ITEM.type, intended_use='ถ่ายคลิป',
                             additional_goals=['อธิบายวิธีสมัครสมาชิก'])
    answer = equipment_answer(price_requirement={'maximum': 100, 'user_unit': ITEM.type,
        'catalog_units': [ITEM.type], 'interpretation': 'Same established billing period'})
    case, llm, *_ = make_fast(turn(understanding=decision, knowledge_ids=['account.registration'],
                                  response_mode='equipment', evidence_goal='เลือกอุปกรณ์ถ่ายคลิปในงบ 100 บาทต่อวัน'), answer)
    result = await case.execute(ChatRequestDTO(message='สมัครสมาชิกอย่างไร และแนะนำอุปกรณ์ให้ด้วย'))
    knowledge = await case._knowledge.get_approved_knowledge()
    public_fact = next(article.content for article in knowledge.articles if article.id == 'account.registration')
    assert result.response == public_fact + '\n\n' + answer.answer.replace('{{item:' + ITEM.id + ':name}}', ITEM.name)
    payload = restore_planning_input(json.loads(llm.generate_structured.call_args_list[1].kwargs['prompt']))
    assert payload['app_information_projected'] is True
    assert 'approved_articles' not in payload
    assert 'request' not in payload
    assert 'projected_app_facts' not in payload
    assert not payload['understanding'].get('additional_goals')
    assert public_fact not in json.dumps(payload, ensure_ascii=False)
    assert payload['understanding']['user_goal'] == 'เลือกอุปกรณ์ถ่ายคลิปในงบ 100 บาทต่อวัน'
    assert payload['understanding']['budget_max'] == 100
    assert payload['understanding']['budget_unit'] == ITEM.type
    assert payload['understanding']['intended_use'] == 'ถ่ายคลิป'
    assert 'สมัครสมาชิก' not in json.dumps(payload, ensure_ascii=False)


@pytest.mark.asyncio
async def test_mixed_equipment_answer_cannot_reuse_an_unseparated_user_goal():
    decision = understanding(catalog_operation='selection', information_sufficient=True,
                             next_action='answer', missing_slots=[], additional_goals=['อธิบายวิธีสมัครสมาชิก'])
    case, llm, *_ = make_fast(turn(understanding=decision, knowledge_ids=['account.registration'],
                                  response_mode='equipment'), equipment_answer())
    with pytest.raises(ValidationError, match='separate equipment goal'):
        await case.execute(ChatRequestDTO(message='สมัครสมาชิกอย่างไร และแนะนำอุปกรณ์ให้ด้วย'))
    assert llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_declared_remaining_equipment_task_cannot_be_dropped_by_document_stage():
    decision = understanding(intent='item_inquiry', catalog_operation='none', information_sufficient=True,
                             next_action='answer', missing_slots=[], additional_goals=['อธิบายวิธีสมัครสมาชิก'])
    case, llm, *_ = make_fast(turn(understanding=decision, knowledge_ids=['account.registration'],
                                  response_mode='documents', evidence_goal='อธิบายคุณสมบัติอุปกรณ์ที่เลือก'))
    with pytest.raises(ValidationError, match='equipment task requires an evidence stage'):
        await case.execute(ChatRequestDTO(message='สมัครสมาชิกอย่างไร และอุปกรณ์นี้มีคุณสมบัติอะไร'))
    assert llm.generate_structured.await_count == 1


@pytest.mark.asyncio
async def test_rejected_app_manual_plan_fails_over_to_a_clean_recommendation(tmp_path):
    import httpx

    from app.infrastructure.llm.cascade_llm_service import CascadeLLMService
    from app.infrastructure.llm.groq_client import GroqClient
    from native_turn_fixture import native_fixture
    from test_provider_runtime import RUNTIME, envelope

    message = 'แนะนำอุปกรณ์ตามความต้องการที่ตอบไว้'
    decision = understanding(catalog_operation='selection', information_sufficient=True,
                             next_action='answer', missing_slots=[], additional_goals=[])
    clean = turn(understanding=decision, knowledge_ids=[], response_mode='equipment')
    invalid = clean.model_copy(update={'knowledge_ids': ['wallet.current_implementation']})
    outputs = [NativeTurnPlan.model_validate(native_fixture(plan, message)).model_dump(mode='json', by_alias=True)
               for plan in (invalid, clean)]
    outputs.append(equipment_answer().model_dump(mode='json', by_alias=True))
    payloads = []

    def respond(request):
        payloads.append(json.loads(request.content))
        return httpx.Response(200, json=envelope(json.dumps(outputs[len(payloads) - 1], ensure_ascii=False)))

    runtime = RUNTIME.model_copy(update={
        'quota_ledger': RUNTIME.quota_ledger.model_copy(update={'path': str(tmp_path / 'quota.json')}),
        'providers': tuple(profile.model_copy(update={'quota': profile.quota.model_copy(
            update={'tokens_per_window': 100000, 'tokens_per_day': 1000000})}) for profile in RUNTIME.providers),
    })
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as http:
        service = CascadeLLMService(runtime=runtime,
            groq_client=GroqClient(api_key='fixture', runtime=runtime, http_client=http))
        case, *_ = make_fast(clean, equipment_answer())
        case._llm = service
        try:
            result = await case.execute(ChatRequestDTO(message=message))
            assert result.items and not any(ref.kind == 'app_knowledge' for ref in result.references)
            assert len(payloads) == 3
            assert 'plan_app_information_requires_a_requested_goal' in payloads[1]['messages'][0]['content']
        finally:
            await service.aclose()


@pytest.mark.asyncio
async def test_repair_preserves_only_the_requested_public_app_fact():
    decision = understanding(catalog_operation='selection', information_sufficient=True,
                             next_action='answer', missing_slots=[], additional_goals=['อธิบายวิธีสมัครสมาชิก'])
    plan = turn(understanding=decision, knowledge_ids=['account.registration'], response_mode='equipment',
                evidence_goal='แนะนำอุปกรณ์ให้ด้วย')
    answer = equipment_answer()
    case, llm, *_ = make_fast(plan, answer)
    rejection = GuidanceGenerationError('response_quality_rejected')
    rejection.review = {'issues': [], 'assessments': []}
    case._review.execute.side_effect = [rejection, None]

    async def generate(**kwargs):
        stage = CURRENT_GENERATION.get()
        stage.provenance = Provenance('fixture', 'writer')
        if stage.name == 'planning':
            return plan
        if stage.name == 'evidence':
            return answer
        assert stage.name == 'repair'
        return kwargs['schema'].model_validate({**answer.model_dump(), 'questions': []})

    llm.generate_structured.side_effect = generate
    result = await case.execute(ChatRequestDTO(message='สมัครสมาชิกอย่างไร และแนะนำอุปกรณ์ให้ด้วย'))
    knowledge = await case._knowledge.get_approved_knowledge()
    public_fact = next(article.content for article in knowledge.articles if article.id == 'account.registration')
    assert result.response == public_fact + '\n\n' + answer.answer.replace('{{item:' + ITEM.id + ':name}}', ITEM.name)
    assert case._review.execute.await_count == 2
    payload = restore_planning_input(json.loads(llm.generate_structured.call_args_list[-1].kwargs['prompt']))
    assert payload['request'] == {'equipment_goal': plan.evidence_goal}
    assert payload['approved_articles'] == []
    assert public_fact not in payload['rejected_draft']['response']
    assert case._review.execute.call_args.args[1].response.startswith(public_fact)


def test_public_app_facts_do_not_contain_internal_implementation_notes():
    path = Path(__file__).resolve().parents[1] / 'knowledge/app_knowledge.json'
    articles = json.loads(path.read_text(encoding='utf-8'))['articles']
    for article in articles:
        if article['status'] == 'approved':
            assert not any(marker in article['content'] for marker in
                           ('backend', 'fetchWallet', 'topUp', 'OAuth', 'configuration', 'provider', 'KYC', 'โค้ด'))


@pytest.mark.parametrize('name, model', [('turn_plan', TurnPlan), ('native_turn_plan', NativeTurnPlan)])
def test_exported_planning_contract_preserves_app_request_scope(name, model):
    path = Path(__file__).resolve().parents[1] / f'config/schemas/{name}.schema.json'
    assert json.loads(path.read_text(encoding='utf-8')) == model.model_json_schema()
