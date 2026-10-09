import asyncio
import json
from pathlib import Path
from unittest.mock import AsyncMock

import pytest

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.domain.exceptions import GuidanceGenerationError
from app.infrastructure.runtime.documents import ValidatedFile
from app.infrastructure.runtime.schema import RuntimeDocument


def test_approved_deadlines_allow_all_flows_thirty_seconds():
    runtime = ValidatedFile(Path(__file__).resolve().parents[1] / 'config/ai_runtime.json', RuntimeDocument).read()[0]
    assert runtime.general.hard_deadline_seconds == runtime.equipment.hard_deadline_seconds == runtime.technical_hard_deadline_seconds == 30
    assert runtime.http.logical_call_deadline_seconds == 30
    assert runtime.http.timeout_seconds >= runtime.http.logical_call_deadline_seconds
    assert (runtime.general.logical_calls, runtime.equipment.logical_calls, runtime.max_failovers_per_logical_call) == (4, 5, 1)


def stream_case():
    case = object.__new__(ProcessChatMessageUseCase)
    case._heartbeat = .01
    case._chunk_size = 2
    return case


@pytest.mark.asyncio
async def test_ready_carries_complete_validated_reply_before_character_deltas():
    case = stream_case()
    case.execute = AsyncMock(return_value=ChatResponseDTO(response='คำตอบครบถ้วน', suggested_replies=['ถัดไป']))
    events = [event async for event in case.execute_stream(ChatRequestDTO(message='fixture'))]
    ready = next(event for event in events if event.startswith('event: ready\n'))
    payload = json.loads(ready.split('data: ', 1)[1])
    assert payload['answer'] == 'คำตอบครบถ้วน'
    assert payload['suggested_replies'] == ['ถัดไป']
    assert events.index(ready) < next(i for i, event in enumerate(events) if event.startswith('event: delta\n'))
    done = next(event for event in events if event.startswith('event: done\n'))
    assert json.loads(done.split('data: ', 1)[1]) == payload


@pytest.mark.asyncio
async def test_rejected_draft_never_emits_ready_or_delta():
    case = stream_case()
    case.execute = AsyncMock(side_effect=GuidanceGenerationError('response_quality_rejected'))
    events = []
    with pytest.raises(GuidanceGenerationError):
        async for event in case.execute_stream(ChatRequestDTO(message='fixture')):
            events.append(event)
    assert not any(event.startswith(('event: ready\n', 'event: delta\n')) for event in events)


@pytest.mark.asyncio
async def test_disconnected_stream_cancels_pending_generation():
    case = stream_case()
    cancelled = asyncio.Event()
    async def pending(request):
        try:
            await asyncio.sleep(10)
        finally:
            cancelled.set()
    case.execute = pending
    stream = case.execute_stream(ChatRequestDTO(message='fixture'))
    await anext(stream)
    await anext(stream)
    await stream.aclose()
    assert cancelled.is_set()
