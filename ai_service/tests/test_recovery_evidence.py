"""Recovery uses actual answers and sufficient authoritative claim evidence."""
import json
from pathlib import Path
from types import SimpleNamespace

from app.application.dtos.chat_dto import ChatRequestDTO
from app.application.services.recovery_evidence import request_evidence, catalog_evidence
from app.application.services.conversation_context import ContextLimits
from app.domain.entities.item import Item


def test_completed_answers_keep_selected_labels_values_ids_and_original_request():
    raw=json.loads((Path(__file__).parent/'fixtures/questionnaire_recovery_request.json').read_text(encoding='utf-8'))
    request=ChatRequestDTO.model_validate(raw['request'])
    original=request.model_dump(mode='json')
    view=request_evidence(request,ContextLimits(16,24000))
    assert view['message']==request.message
    assert view['questionnaire_answers']==original['questionnaire_answers']
    assert {k:view['history'][0][k] for k in ('role','content')}==original['history'][0]
    for question,answer in zip(view['context']['questions'],request.questionnaire_answers):
        selected=next(q for q in original['context']['questions'] if q['id']==answer.question_id)
        choice=next(c for c in selected['choices'] if c['id']==answer.option_id)
        assert [{k:c[k] for k in ('id','label','action_value')} for c in question['choices']]==[
            {k:choice[k] for k in ('id','label','action_value')}]
        assert question['options']==[choice['label']]
    assert request.model_dump(mode='json')==original
    assert len(view['history'][1]['content']['questions'][1]['choices'])==1


def test_partial_questionnaire_preserves_unanswered_choices():
    raw=json.loads((Path(__file__).parent/'fixtures/questionnaire_recovery_request.json').read_text(encoding='utf-8'))
    request=ChatRequestDTO.model_validate(raw['request'])
    request.questionnaire_answers=request.questionnaire_answers[:1]
    view=request_evidence(request,ContextLimits(16,24000))
    assert view['context']['questions']==request.context.model_dump(mode='json',exclude_defaults=True)['questions']


def test_inventory_scalar_facts_and_claimed_descriptions_survive_projection():
    items=[Item(id='a',name='Camera',category='Photo',price=500,type='วัน',description='Authoritative A'),
           Item(id='b',name='Tripod',category='Photo',price=50,type='วัน',description='Authoritative B')]
    draft=SimpleNamespace(items=[SimpleNamespace(id='a')],references=[])
    view=catalog_evidence(items,draft)
    rows=[dict(zip(view['columns'],row)) for row in view['rows']]
    assert rows[0]['description']=='Authoritative A'
    assert rows[1]['description'] is None
    for row,item in zip(rows,items):
        assert (row['id'],row['name'],row['price'],row['type'],row['category'],row['status']) == (
            item.id,item.name,item.price,item.type,item.category,item.status)
    assert view['description_scope']['others']=='unknown in this view'
    # ผู้ตรวจรอบสุดท้ายเห็น description เต็มของสินค้าใหม่ที่คำตอบกู้เลือก
    replacement=SimpleNamespace(items=[SimpleNamespace(id='b')],references=[])
    final=catalog_evidence(items,replacement)
    assert dict(zip(final['columns'],final['rows'][1]))['description']=='Authoritative B'
    # no_matches ต้องเก็บ description ทั้งคลังเพื่อประเมินว่าไม่มีตัวเลือกจริง
    no_matches=catalog_evidence(items,SimpleNamespace(items=[],references=[]))
    assert [dict(zip(no_matches['columns'],r))['description'] for r in no_matches['rows']]==[
        'Authoritative A','Authoritative B']
