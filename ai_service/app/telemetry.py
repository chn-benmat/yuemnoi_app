"""เก็บเฉพาะ metadata ต่อคำขอ ไม่เก็บเนื้อหาหรือข้อมูลรับรอง"""
import logging
import time
from contextlib import contextmanager
from contextvars import ContextVar

logger = logging.getLogger("uvicorn.error")
request_id = ContextVar("ai_request_id", default="-")
model_calls = ContextVar("ai_model_calls", default=0)


@contextmanager
def stage(name):
    start = time.perf_counter()
    try:
        yield
    finally:
        logger.info("ai_stage request_id=%s stage=%s duration_ms=%.2f", request_id.get(), name, (time.perf_counter()-start)*1000)
