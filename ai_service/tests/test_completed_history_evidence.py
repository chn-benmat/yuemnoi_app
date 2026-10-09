import json
from pathlib import Path
from pydantic import BaseModel
from app.core.config import settings
from app.application.services.review_input import restore_planning_input, compact_planning_input
from app.infrastructure.llm.groq_client import GroqClient
from native_turn_fixture import current_capture_schema
from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.recovery_evidence import request_evidence
from app.application.services.conversation_context import ContextLimits


def historical_question(selected_id='camera:cap'):
    return {'id': 'budget', 'dimension': 'budget_max', 'title': 'งบต่อวัน',
        'choices': [{'id': 'base', 'label': 'ค่าตั้งต้น', 'action_value': 'base'}],
        'options': ['ค่าตั้งต้น'], 'selected': 'ไม่เกิน 650 บาทต่อวัน',
        'selected_option_id': selected_id, 'branch_question_id': 'kind',
        'branch_titles': {'camera': 'งบกล้องต่อวัน'},
        'branch_options': {'camera': ['ไม่เกิน 650 บาทต่อวัน', 'ไม่จำกัดงบ']},
        'branch_choices': {'camera': [
            {'id': 'camera:cap', 'label': 'ไม่เกิน 650 บาทต่อวัน', 'action_value': 'ไม่เกิน 650 บาทต่อวัน'},
            {'id': 'camera:any', 'label': 'ไม่จำกัดงบ', 'action_value': 'ไม่จำกัดงบ'}]}}


def test_selected_history_keeps_exact_branch_answer_when_current_context_has_no_questionnaire():
    kind = {'id': 'kind', 'dimension': 'category', 'title': 'ประเภท',
        'choices': [{'id': 'camera', 'label': 'กล้อง', 'action_value': 'camera'},
                    {'id': 'audio', 'label': 'ลำโพง', 'action_value': 'audio'}],
        'options': ['กล้อง', 'ลำโพง'], 'selected': 'กล้อง', 'selected_option_id': 'camera'}
    budget = historical_question()
    request = ChatRequestDTO(message='เปลี่ยนเป็นคอมแทน', history=[{'role': 'assistant',
        'content': json.dumps({'answer': 'เลือกข้อมูล', 'questions': [kind, budget]}, ensure_ascii=False)}])
    original = request.model_dump()
    view = request_evidence(request, ContextLimits(16, 24000))
    content = view['history'][0]['content']
    assert isinstance(content, dict)
    questions = content['questions']
    assert [choice['id'] for choice in questions[0]['choices']] == ['camera']
    assert questions[1]['title'] == 'งบกล้องต่อวัน'
    assert [{key: choice[key] for key in ('id', 'label', 'action_value')} for choice in questions[1]['choices']] == [
        budget['branch_choices']['camera'][0]]
    assert questions[1]['selected_option_id'] == 'camera:cap'
    assert 'branch_choices' not in questions[1]
    assert request.model_dump() == original


def test_unknown_history_selection_preserves_original_evidence_instead_of_inventing_an_answer():
    question = historical_question('unknown')
    request = ChatRequestDTO(message='คุยต่อ', history=[{'role': 'assistant',
        'content': json.dumps({'questions': [question]}, ensure_ascii=False)}])
    view = request_evidence(request, ContextLimits(16, 24000))
    content = view['history'][0]['content']
    if isinstance(content, str):
        content = json.loads(content)
    assert content['questions'] == [question]


def native_followup():
    fixture = json.loads((Path(__file__).parent / 'fixtures/native_questionnaire_followup.json').read_text(encoding='utf-8'))
    request = ChatRequestDTO.model_validate(fixture['request'])
    return fixture, request, request_evidence(request, ContextLimits(16, 24000))


def test_native_followup_context_retains_only_exact_historical_answers():
    _, request, view = native_followup()
    original = request.model_dump()
    expected = {question['id']: question['selected_option_id']
        for message in view['history'] if isinstance(message['content'], dict)
        for question in message['content'].get('questions', [])}
    assert expected
    for question in view['context']['questions']:
        assert [choice['id'] for choice in question['choices']] == [expected[question['id']]]
    assert request.model_dump() == original


def test_actual_followup_planning_fits_unchanged_capacity_after_answer_projection():
    fixture, _, view = native_followup()
    planning = restore_planning_input(json.loads(fixture['prompt']))
    planning['client_context'] = view['context']
    assert len(planning['conversation']['messages']) == len(view['history'])
    for message, projected in zip(planning['conversation']['messages'], view['history']):
        message['content'] = projected['content']
    document = current_capture_schema(fixture['schema'])
    schema = type(document['title'], (BaseModel,), {'model_json_schema': staticmethod(lambda: document)})
    instruction = json.loads(settings.INTERPRETATION_POLICY_PATH.read_text(encoding='utf-8'))['turn_instruction']
    client = GroqClient(api_key='fixture')
    kwargs = dict(prompt=json.dumps(compact_planning_input(planning), ensure_ascii=False, separators=(',', ':')),
        schema=schema, system_instruction=instruction)
    for profile in client.runtime.providers:
        if profile.enabled and profile.protocol == client.protocol:
            assert client.request_cost('generate_structured', getattr(settings, profile.model_setting), kwargs) <= profile.quota.tokens_per_window
