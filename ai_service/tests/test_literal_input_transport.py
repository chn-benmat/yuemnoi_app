import json
from app.application.services.review_input import compact_planning_input, restore_planning_input
from app.infrastructure.llm.reference_transport import encode_references, decode_references


def test_literal_descendants_cannot_be_hidden_by_an_ancestor_alias_or_table():
    questions = [{'title': 'คำถามที่ผู้ใช้เห็นจริง' * 12, 'options': ['หนึ่ง', 'สอง']}]
    original = {'archive': {'questions': questions}, 'visible': {'questions': questions}}
    compacted = compact_planning_input(original, literal_paths=('/visible/questions',))
    assert compacted['visible']['questions'] == questions
    assert restore_planning_input(compacted) == original
    rows = {'records': [{'questions': questions, 'index': index} for index in range(3)]}
    compacted = compact_planning_input(rows, literal_paths=('/records/0/questions',))
    assert compacted['records'][0]['questions'] == questions
    assert restore_planning_input(compacted) == rows


def test_literal_dictionary_marker_and_exact_text_survive_actual_reference_transport():
    original = {'visible': {'marker': {'$text': 2}, 'label': 'ข้อความต้นฉบับ'},
                'repeated': [{'label': 'ข้อความที่ซ้ำ' * 3, 'index': index} for index in range(8)],
                'source_message_ids': ['message:' + 'a' * 64]}
    compacted = compact_planning_input(original, literal_paths=('/visible',))
    assert 'input_dictionary' in compacted
    prompt, _, aliases = encode_references(json.dumps(compacted, ensure_ascii=False), {'type': 'object'})
    wire = json.loads(prompt)
    assert wire['visible'] == original['visible']
    assert decode_references(restore_planning_input(wire), aliases) == original
