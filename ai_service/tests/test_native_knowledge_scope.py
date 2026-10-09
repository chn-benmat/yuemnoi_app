"""Dynamic catalog enums must retain the semantic scope of knowledge selection."""
import pytest

from app.application.dtos.chat_dto import ChatRequestDTO
from app.domain.entities.turn_plan import NativeTurnPlan
from app.infrastructure.llm.provider_client import native_schema
from test_response_repair import stack


@pytest.mark.asyncio
async def test_planning_wire_preserves_knowledge_scope_when_binding_authorized_ids():
    case, llm, _, _ = stack()

    class Captured(Exception):
        pass

    async def inspect(**kwargs):
        document = native_schema(kwargs['schema'])
        for name in ('knowledge_ids', 'unverified_topic_ids'):
            # ผูก enum ตามเอกสารจริงแล้วต้องไม่ทำคำอธิบายขอบเขตการเลือกหาย
            assert document['properties'][name].get('description') == NativeTurnPlan.model_fields[name].description
        raise Captured

    llm.generate_structured.side_effect = inspect
    with pytest.raises(Captured):
        await case.execute(ChatRequestDTO(message='อยากเช่ามือถือ'))
