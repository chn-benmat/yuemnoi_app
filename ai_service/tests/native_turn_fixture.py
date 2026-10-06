"""Current native contract for simulated replay regressions, never live evidence."""
from app.application.services.conversation_context import message_source_id


def native_fixture(plan, message='fixture'):
    data = plan.model_dump()
    data['stage'] = {key: data.pop(key) for key in ('response_mode', 'message', 'questions')}
    for group in ('known_facts', 'user_constraints'):
        for fact in data['understanding'][group]:
            fact['source_message_ids'] = [message_source_id('user', message) if value == 'current' else value
                                          for value in fact['source_message_ids']]
    return data
