"""Current native contract for simulated replay regressions, never live evidence."""
from app.application.services.conversation_context import message_source_id
from copy import deepcopy
from app.domain.entities.turn_plan import NativeTurnPlan


def current_capture_schema(snapshot):
    """Keep captured ID/unit constraints while applying current shared stage schemas."""
    document = deepcopy(snapshot)
    current = NativeTurnPlan.model_json_schema()
    stage_definitions = set()
    def collect(value):
        if isinstance(value, list):
            for child in value:
                collect(child)
        elif isinstance(value, dict):
            reference = value.get('$ref', '').removeprefix('#/$defs/')
            if reference in current.get('$defs', {}) and reference not in stage_definitions:
                stage_definitions.add(reference)
                collect(current['$defs'][reference])
            for child in value.values():
                collect(child)
    collect(current['properties']['stage'])
    for name, definition in current.get('$defs', {}).items():
        if name in document.get('$defs', {}) or name in stage_definitions:
            document['$defs'][name] = definition
    document['properties']['stage'] = current['properties']['stage']
    return document


def native_questions(questions):
    for question in questions:
        if 'dimension' in question:
            dimension = question.pop('dimension')
            question['slot'] = ({'kind': 'spending_ceiling'} if dimension == 'budget_max'
                                else {'kind': 'other_requirement', 'dimension': dimension})
        for version in [question, *question.get('branches', [])]:
            version['ask'] = version.pop('title')
            version.pop('choice_mode', None)
            unrestricted = version.pop('unrestricted_choice', None)
            for choice in version['choices']:
                choice['value_kind'] = 'specified'
            if unrestricted is not None:
                version['choices'].append({**unrestricted, 'value_kind': 'unrestricted'})
    return questions


def native_fixture(plan, message='fixture'):
    data = plan.model_dump()
    data['stage'] = {key: data.pop(key) for key in ('response_mode', 'message', 'questions')}
    data['stage']['questions'] = native_questions(data['stage']['questions'])
    data['stage']['catalog_operation'] = {'kind': data['understanding'].pop('catalog_operation')}
    for key in ('next_action', 'information_sufficient', 'missing_slots'):
        data['understanding'].pop(key)
    for group in ('known_facts', 'user_constraints'):
        for fact in data['understanding'][group]:
            fact['source_message_ids'] = [message_source_id('user', message) if value == 'current' else value
                                          for value in fact['source_message_ids']]
    return data
