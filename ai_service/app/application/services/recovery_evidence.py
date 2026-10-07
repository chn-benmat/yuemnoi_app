"""Evidence views retain actual answers and every claim's authoritative fields."""
import json
from app.application.services.conversation_context import conversation_context
from app.application.services.catalog_guidance import catalog_snapshot,compact_catalog
from app.domain.entities.clarification import QuestionStep


def request_evidence(request, limits):
    data=request.model_dump(mode='json')
    data['history']=conversation_context(request.history,limits)['messages'] if limits else data['history']
    if request.context:
        data['context']=request.context.model_dump(mode='json',exclude_defaults=True)
        answered={answer.question_id:answer for answer in request.questionnaire_answers}
        if answered and set(answered)=={q.id for q in request.context.questions}:
            # ทางเลือกเก่าที่ไม่ได้เลือกเป็น metadata UI ไม่ใช่คำตอบของผู้ใช้
            def selected_view(question):
                answer=answered.get(question.get('id'))
                if answer is None: return question
                result=dict(question)
                source_answer = answered.get(question.get('branch_question_id'))
                if source_answer and source_answer.option_id:
                    result['title'] = question.get('branch_titles', {}).get(source_answer.option_id, question['title'])
                for field in ('branch_titles', 'branch_options', 'branch_choices', 'branch_question_id'):
                    result.pop(field, None)
                choices=[c for c in question.get('choices',[]) if c.get('id')==answer.option_id]
                result['choices']=choices
                result['options']=[c['label'] for c in choices]
                if answer.text is not None: result['typed_answer']=answer.text
                # ละค่าเริ่มต้นของ UI ให้ข้อมูลข้อเดียวกันยุบซ้ำได้ แต่คงคำตอบและ metadata อื่น
                normalized = QuestionStep.model_validate(result).model_dump(mode='json', exclude_defaults=True)
                return {**normalized, **{key:value for key,value in result.items() if key not in QuestionStep.model_fields}}
            data['context']['questions']=[selected_view(q) for q in data['context']['questions']]
            for message in data['history']:
                content=message['content']
                if isinstance(content,str):
                    try:content=json.loads(content)
                    except ValueError:continue
                if isinstance(content,dict) and isinstance(content.get('questions'),list):
                    message['content']={**content,'questions':[selected_view(q) for q in content['questions']]}
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
