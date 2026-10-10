import asyncio
from collections.abc import Callable
from app.domain.identity import IdentityAnalyzer, IdentityAnalysis

class IdentityRuntime:
    """คิวจำกัดหนึ่งงาน รวมถึงงานที่ HTTP timeout แต่เธรดยังประมวลผลอยู่"""
    def __init__(self, factory: Callable[[],IdentityAnalyzer], timeout:float, queue_timeout:float):
        self.factory,self.timeout,self.queue_timeout = factory,timeout,queue_timeout
        self.engine: IdentityAnalyzer | None = None
        self.semaphore=asyncio.Semaphore(1)

    async def start(self):
        self.engine=await asyncio.to_thread(self.factory)

    async def analyze(self, card:bytes, selfie:bytes) -> IdentityAnalysis:
        return await self._run("analyze", card, selfie)

    async def read_card(self, card:bytes) -> dict:
        return await self._run("read_card", card)

    async def _run(self, method:str, *args):
        if self.engine is None: raise RuntimeError("identity_unavailable")
        await asyncio.wait_for(self.semaphore.acquire(),timeout=self.queue_timeout)
        task=asyncio.create_task(asyncio.to_thread(getattr(self.engine,method),*args))
        def completed(finished):
            self.semaphore.release()
            if not finished.cancelled(): finished.exception()
        task.add_done_callback(completed)
        return await asyncio.wait_for(asyncio.shield(task),timeout=self.timeout)
