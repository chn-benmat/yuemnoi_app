import asyncio
import json

import pytest

from app.application.dtos.chat_dto import ChatRequestDTO, ChatResponseDTO
from app.application.use_cases.process_chat_message_use_case import ProcessChatMessageUseCase
from app.domain.exceptions import GuidanceGenerationError
from app.domain.interfaces.generation_stage import generation_stage


def stream_case(execute):
    case = object.__new__(ProcessChatMessageUseCase)
    case._heartbeat = 1
    case._chunk_size = 64
    case.execute = execute
    return case


def status_payload(event):
    assert event.startswith('event: status\n')
    return json.loads(event.split('data: ', 1)[1])


@pytest.mark.asyncio
@pytest.mark.parametrize('stages', [
    ['planning', 'evidence', 'review'],
    ['planning', 'review'],
    ['planning', 'evidence', 'review', 'repair', 'review'],
])
async def test_status_is_visible_while_each_actual_stage_is_still_running(stages):
    gates = [asyncio.Event() for _ in stages]
    labels = {
        'planning': 'กำลังวิเคราะห์คำถาม',
        'evidence': 'กำลังสร้างคำตอบ',
        'review': 'กำลังตรวจคำตอบ',
        'repair': 'กำลังสรุปคำคำตอบ',
    }

    async def execute(request):
        for stage, gate in zip(stages, gates):
            with generation_stage(stage):
                await gate.wait()
        return ChatResponseDTO(response='คำตอบที่ตรวจแล้ว')

    stream = stream_case(execute).execute_stream(ChatRequestDTO(message='คำถาม'))
    try:
        assert status_payload(await anext(stream)) == {
            'step': 'preparing', 'message': 'กำลังเตรียมข้อมูล',
        }
        for stage, gate in zip(stages, gates):
            assert status_payload(await anext(stream)) == {
                'step': stage, 'message': labels[stage],
            }
            assert not gate.is_set()
            gate.set()
        assert (await anext(stream)).startswith('event: ready\n')
    finally:
        await stream.aclose()


@pytest.mark.asyncio
async def test_concurrent_streams_keep_their_own_stage_events():
    async def execute(request):
        stages = ['planning', 'review'] if request.message == 'first' else ['evidence', 'repair', 'review']
        for stage in stages:
            with generation_stage(stage):
                await asyncio.sleep(0)
        return ChatResponseDTO(response=request.message)

    case = stream_case(execute)

    async def collect(message):
        return [status_payload(event)['step']
                async for event in case.execute_stream(ChatRequestDTO(message=message))
                if event.startswith('event: status\n')]

    assert await asyncio.gather(collect('first'), collect('second')) == [
        ['preparing', 'planning', 'review'],
        ['preparing', 'evidence', 'repair', 'review'],
    ]


@pytest.mark.asyncio
async def test_failed_review_preserves_status_but_never_exposes_draft():
    async def execute(request):
        with generation_stage('review'):
            raise GuidanceGenerationError('response_quality_rejected')

    events = []
    with pytest.raises(GuidanceGenerationError, match='response_quality_rejected'):
        async for event in stream_case(execute).execute_stream(ChatRequestDTO(message='คำถาม')):
            events.append(event)
    assert [status_payload(event)['step'] for event in events] == ['preparing', 'review']


@pytest.mark.asyncio
async def test_disconnect_during_stage_cancels_generation():
    cancelled = asyncio.Event()

    async def execute(request):
        try:
            with generation_stage('evidence'):
                await asyncio.Event().wait()
        finally:
            cancelled.set()

    stream = stream_case(execute).execute_stream(ChatRequestDTO(message='คำถาม'))
    await anext(stream)
    assert status_payload(await anext(stream))['step'] == 'evidence'
    await stream.aclose()
    assert cancelled.is_set()
