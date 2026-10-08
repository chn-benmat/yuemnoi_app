"""Opt-in replay through the production container, with a private local artifact."""

import argparse
import asyncio
import json
from pathlib import Path

from app.application.dtos.chat_dto import ChatRequestDTO
from app.domain.interfaces.chat_diagnostics import diagnostic_scope, record_diagnostic
from app.domain.interfaces.generation_stage import GENERATION_RECORDING


def redact_configured_credentials(value, configuration):
    """Secrets are not captured; also redact accidental model echoes of known keys."""
    sensitive = []
    for name in type(configuration).model_fields:
        if name.endswith(("_KEY", "_TOKEN", "_PASSWORD", "_QUOTA_ACCOUNT_ID")):
            secret = getattr(configuration, name, None)
            if isinstance(secret, str) and secret:
                sensitive.append(secret)

    def redact(item):
        if isinstance(item, str):
            for secret in sensitive:
                item = item.replace(secret, "[redacted]")
            return item
        if isinstance(item, list):
            return [redact(child) for child in item]
        if isinstance(item, dict):
            return {key: redact(child) for key, child in item.items()}
        return item
    return redact(value)


async def capture_chat(request, container, *, stream=False):
    """Used only after an explicit CLI invocation, never from a production endpoint."""
    records = []
    recording_token = GENERATION_RECORDING.set(records)
    with diagnostic_scope() as trace:
        artifact = {"trace_id": trace.trace_id, "request": request.model_dump(mode="json")}
        try:
            await container.start()
            if stream:
                artifact["stream_events"] = [event async for event in
                    container.process_chat_message_use_case.execute_stream(request)]
            else:
                result = await container.process_chat_message_use_case.execute(request)
                artifact["response"] = result.model_dump(mode="json")
            record_diagnostic("outcome")
        except Exception as error:
            # ไม่เก็บ exception text หรือ transport envelope ซึ่งอาจมีข้อมูลลับ
            code = getattr(error, "code", None) or "processing_failed"
            artifact["error"] = {"error_code": code, "type": type(error).__name__}
            retry = getattr(error, "retry_after", None)
            if retry is not None:
                artifact["error"]["retry_after_seconds"] = retry
            for name in ("draft", "review"):
                details = getattr(error, name, None)
                if details is not None:
                    artifact["error"][name] = details
            record_diagnostic("outcome", error_code=code)
        finally:
            try:
                await container.aclose()
            finally:
                GENERATION_RECORDING.reset(recording_token)
        artifact["diagnostics"] = trace.summary()
        artifact["generation_records"] = records
        return artifact


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", type=Path, required=True,
                        help="JSON file containing exactly one ChatRequestDTO")
    parser.add_argument("--output", type=Path, required=True,
                        help="New private local JSON artifact; never overwrites an existing file")
    parser.add_argument("--stream", action="store_true", help="Replay the SSE use case")
    args = parser.parse_args(argv)
    if not args.output.parent.is_dir() or args.output.exists():
        parser.error("Output must be a new file in an existing local directory")
    request = ChatRequestDTO.model_validate_json(args.request.read_text(encoding="utf-8"))
    # โหลด config และ container หลังผู้ใช้เลือกไฟล์อย่างชัดเจนเท่านั้น
    from app.core.config import settings
    from app.core.container import Container
    artifact = asyncio.run(capture_chat(request, Container(), stream=args.stream))
    artifact = redact_configured_credentials(artifact, settings)
    # เปิดแบบ exclusive ก่อนเขียน ป้องกันเขียนทับ artifact ที่ถูกสร้างพร้อมกัน
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(artifact, output, ensure_ascii=False, indent=2)
    print(f"Diagnostic trace {artifact['trace_id']} saved to {args.output.resolve()}")
    return 1 if "error" in artifact else 0


if __name__ == "__main__":
    raise SystemExit(main())
