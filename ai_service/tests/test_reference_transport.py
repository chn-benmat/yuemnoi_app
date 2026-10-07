import json
from app.infrastructure.llm.reference_transport import encode_references,decode_references
from app.application.services.review_input import restore_planning_input


def test_opaque_ids_and_explicit_tokens_roundtrip_without_changing_text():
    identifier='opaque-authoritative-item-'*4
    source='message:'+'a'*64
    payload={'catalog':{'columns':['id','name'],'rows':[[identifier,'Source name']]},
        'current_message':{'id':source,'content':'User phrase stays exactly unchanged'},
        'eligible_item_ids':[identifier],'source_message_ids':[source],
        'answer':'See {{item:'+identifier+':name}}'}
    schema={'enum':[identifier]}
    prompt,wire_schema,aliases=encode_references(json.dumps(payload,ensure_ascii=False),schema)
    restored=restore_planning_input(json.loads(prompt))
    assert decode_references(restored,aliases)==payload
    assert decode_references(wire_schema,aliases)==schema
    assert len(prompt)<len(json.dumps(payload,ensure_ascii=False))
    assert restored['current_message']['content']==payload['current_message']['content']


def test_non_json_and_alias_collisions_preserve_original_input():
    schema={'type':'object'}
    assert encode_references('Plain user text',schema)==('Plain user text',schema,{})
    prompt=json.dumps({'id':'long-original-id','message':'@ref0'})
    assert encode_references(prompt,schema)==(prompt,schema,{})
