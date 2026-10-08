"""Lossless request-local handles for opaque IDs; no interpretation of user text."""
import json
from app.application.services.review_input import compact_planning_input, restore_planning_input

_ID_FIELDS = frozenset(('id','source_id','question_id','active_question_id'))
_ID_LISTS = frozenset(('source_message_ids','supporting_item_ids','referenced_item_ids','eligible_item_ids'))


def encode_references(prompt, document):
    try:
        data = json.loads(prompt)
    except (ValueError, TypeError):
        return prompt, document, {}
    if not isinstance(data,dict):
        return prompt, document, {}
    literal_paths = tuple(data.get('input_literal_paths', ()))
    if 'input_references' in data:
        data = restore_planning_input(data)
    aliases = {}
    def add(value):
        if isinstance(value,str) and value not in aliases:
            handle = '@ref' + str(len(aliases))
            if len(value) > len(handle): aliases[value] = handle
    def collect(value):
        if isinstance(value,dict):
            for key,child in value.items():
                if key in _ID_FIELDS: add(child)
                elif key in _ID_LISTS and isinstance(child,list):
                    for identifier in child: add(identifier)
                collect(child)
            columns,rows = value.get('columns'),value.get('rows')
            if isinstance(columns,list) and isinstance(rows,list):
                for index,key in enumerate(columns):
                    if key in _ID_FIELDS:
                        for row in rows:
                            if isinstance(row,list) and len(row)>index: add(row[index])
        elif isinstance(value,list):
            for child in value: collect(child)
    collect(data)
    # ห้ามชนกับข้อความต้นฉบับที่มีค่าเท่ากับ handle จริง
    strings = set()
    def gather(value):
        if isinstance(value,str): strings.add(value)
        elif isinstance(value,dict):
            for child in value.values(): gather(child)
        elif isinstance(value,list):
            for child in value:gather(child)
    gather(data)
    if set(aliases.values()) & strings:
        return prompt, document, {}
    def encode(value):
        if isinstance(value,str):
            if value in aliases: return aliases[value]
            for identifier,handle in aliases.items():
                value=value.replace('{{item:'+identifier+':','{{item:'+handle+':')
            return value
        if isinstance(value,dict): return {key:encode(child) for key,child in value.items()}
        if isinstance(value,list): return [encode(child) for child in value]
        return value
    packed=compact_planning_input(encode(data), literal_paths=literal_paths)
    return json.dumps(packed,ensure_ascii=False,separators=(',',':')),encode(document),{v:k for k,v in aliases.items()}


def decode_references(value, aliases):
    if isinstance(value,str):
        if value in aliases: return aliases[value]
        for handle,identifier in aliases.items():
            value=value.replace('{{item:'+handle+':','{{item:'+identifier+':')
        return value
    if isinstance(value,dict): return {key:decode_references(child,aliases) for key,child in value.items()}
    if isinstance(value,list): return [decode_references(child,aliases) for child in value]
    return value
