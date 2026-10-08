"""Current native contract for simulated replay regressions, never live evidence."""
from app.application.services.conversation_context import message_source_id
from copy import deepcopy
from app.domain.entities.turn_plan import NativeTurnPlan


def current_capture_schema(snapshot):
    """Keep captured ID/unit constraints while applying current shared stage schemas."""
    document = deepcopy(snapshot)
    current = NativeTurnPlan.model_json_schema()
    for name, definition in current.get('$defs', {}).items():
        if name in document.get('$defs', {}):
            document['$defs'][name] = definition
    document['properties']['stage']['description'] = current['properties']['stage']['description']
    return document


def native_questions(questions):
    for question in questions:
        for version in [question, *question.get('branches', [])]:
            version.pop('choice_mode', None)
            unrestricted = version.pop('unrestricted_choice', None)
            for choice in version['choices']:
                choice['choice_kind'] = 'specified'
            if unrestricted is not None:
                version['choices'].append({**unrestricted, 'choice_kind': 'unrestricted'})
    return questions


def native_fixture(plan, message='fixture'):
    data = plan.model_dump()
    data['stage'] = {key: data.pop(key) for key in ('response_mode', 'message', 'questions')}
    native_questions(data['stage']['questions'])
    data['stage']['catalog_operation'] = {'kind': data['understanding'].pop('catalog_operation')}
    for key in ('next_action', 'information_sufficient', 'missing_slots'):
        data['understanding'].pop(key)
    for group in ('known_facts', 'user_constraints'):
        for fact in data['understanding'][group]:
            fact['source_message_ids'] = [message_source_id('user', message) if value == 'current' else value
                                          for value in fact['source_message_ids']]
    return data
