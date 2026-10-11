"""Evidence views retain actual answers and every claim's authoritative fields."""
import json
from app.domain.entities.chat_result import QuestionnaireAnswer
from app.application.services.conversation_context import conversation_context
from app.application.services.catalog_guidance import catalog_snapshot,compact_catalog
from app.domain.entities.clarification import QuestionStep


def request_evidence(request, limits):
    data=request.model_dump(mode='json')
    data['questionnaire_complete'] = request.questionnaire_complete
    data['history']=conversation_context(request.history,limits)['messages'] if limits else data['history']
    answered={answer.question_id:answer for answer in request.questionnaire_answers}
    def selected_view(question, answers):
        answer=answers.get(question.get('id'))
        if answer is None: return question
        source_answer = answers.get(question.get('branch_question_id'))
        choices_source = question.get('choices', [])
        if source_answer and source_answer.option_id:
            choices_source = question.get('branch_choices', {}).get(source_answer.option_id, choices_source)
        choices=[c for c in choices_source if c.get('id')==answer.option_id]
        if answer.option_id and len(choices) != 1:
            return question
        result=dict(question)
        if source_answer and source_answer.option_id:
            result['title'] = question.get('branch_titles', {}).get(source_answer.option_id, question['title'])
        for field in ('branch_titles', 'branch_options', 'branch_choices', 'branch_question_id'):
            result.pop(field, None)
        result['choices']=choices
        result['options']=[c['label'] for c in choices]
        if answer.text is not None: result['typed_answer']=answer.text
        normalized = QuestionStep.model_validate(result).model_dump(mode='json', exclude_defaults=True)
        return {**normalized, **{key:value for key,value in result.items() if key not in QuestionStep.model_fields}}
    if request.context:
        data['context']=request.context.model_dump(mode='json',exclude_defaults=True)
        if request.questionnaire_complete:
            data['context']['questions']=[selected_view(q, answered) for q in data['context']['questions']]
    for message in data['history']:
        content=message['content']
        if isinstance(content,str):
            try:content=json.loads(content)
            except ValueError:continue
        if not isinstance(content,dict) or not isinstance(content.get('questions'),list):
            continue
        # ประวัติ UI มี ID ที่เลือกจริง จึงคงคำตอบได้แม้แชตใหม่ไม่มีแบบสอบถามปัจจุบัน
        historical = {}
        for question in content['questions']:
            selected_id, text = question.get('selected_option_id'), question.get('selected')
            if selected_id or text:
                historical[question['id']] = QuestionnaireAnswer(question_id=question['id'],
                    option_id=selected_id, text=None if selected_id else text)
        complete = set(answered) >= {q.get('id') for q in content['questions']}
        answers = answered if complete else historical
        message['content']={**content,'questions':[selected_view(q, answers) for q in content['questions']]}
    return data


def catalog_evidence(catalog,draft):
    snapshot=catalog_snapshot(catalog)
    cited={item.id for item in draft.items}
    cited.update(ref.id for ref in draft.references if ref.kind=='catalog')
    if not cited:
        return compact_catalog(snapshot)
    # คงรายการทั้งหมดและ scalar facts สำหรับตรวจ scope/ราคา/stock แต่ส่ง
    # description เต็มเฉพาะทุกรายการที่ draft อ้าง ไม่ทำให้ missing evidence เป็น false
    rows=[row if row['id'] in cited else {**row,'description':None} for row in snapshot['items']]
    return {**compact_catalog({**snapshot,'items':rows}),
            'description_scope':{'complete_for_item_ids':sorted(cited),'others':'unknown in this view'}}
