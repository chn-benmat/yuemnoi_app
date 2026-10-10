import asyncio
import io
import threading
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from app.application.identity import IdentityRuntime
from app.core.identity_settings import IdentitySettings
from app.domain.identity import IdentityAnalysis
from app.infrastructure.identity.engine import VisionIdentityEngine
from app.interface.api.v1.endpoints import identity

def client(monkeypatch):
    monkeypatch.setattr(identity.config,"IDENTITY_ENABLED",True)
    monkeypatch.setattr(identity.settings,"INTERNAL_SERVICE_KEY","test-internal-key")
    app=FastAPI()
    app.include_router(identity.router,prefix="/api")
    app.add_middleware(identity.IdentityProtection)
    return TestClient(app)

def test_internal_auth_before_multipart(monkeypatch):
    c=client(monkeypatch)
    r=c.post("/api/identity/analyze",content=b"not a multipart body")
    assert r.status_code==401
    r=c.post("/api/identity/analyze",headers={"X-Internal-Service-Key":"test-internal-key","Content-Length":str(identity.config.IDENTITY_REQUEST_BYTES+1)},content=b"")
    assert r.status_code==413

def test_missing_models_fail_closed(monkeypatch):
    c=client(monkeypatch)
    monkeypatch.setattr(identity.runtime,"engine",None)
    r=c.get("/api/identity/health",headers={"X-Internal-Service-Key":"test-internal-key"})
    assert r.status_code==503 and r.json()=={"ready":False}
    r=c.post("/api/identity/analyze",headers={"X-Internal-Service-Key":"test-internal-key"},files={"card":("a.jpg",b"image"),"selfie":("b.jpg",b"image")})
    assert r.status_code==503
    assert "image" not in r.text

def test_card_only_endpoint_reuses_protection_and_returns_no_images(monkeypatch):
    c=client(monkeypatch)
    async def read_card(data):
        assert data==b"synthetic-card"
        return {"blocks":[]}
    monkeypatch.setattr(identity.runtime,"read_card",read_card)
    assert c.post("/api/identity/read-card",files={"card":("a.jpg",b"synthetic-card")}).status_code==401
    response=c.post("/api/identity/read-card",headers={"X-Internal-Service-Key":"test-internal-key"},files={"card":("a.jpg",b"synthetic-card")})
    assert response.status_code==200 and response.json()=={"blocks":[]}
    assert response.headers["cache-control"]=="no-store"

def test_decoder_rejects_unsupported_images():
    import cv2
    engine=VisionIdentityEngine.__new__(VisionIdentityEngine)
    engine.settings=IdentitySettings(IDENTITY_MAX_PIXELS=100)
    engine.cv=cv2
    data=io.BytesIO();Image.new("RGB",(20,20)).save(data,format="PNG")
    with pytest.raises(ValueError):engine.decode(data.getvalue())
    data=io.BytesIO();Image.new("RGB",(5,5)).save(data,format="GIF")
    with pytest.raises(ValueError):engine.decode(data.getvalue())

@pytest.mark.asyncio
async def test_timeout_keeps_worker_slot_until_thread_finishes():
    released=threading.Event()
    class Blocking:
        calls=0
        def analyze(self,a,b):
            self.calls+=1
            released.wait(2)
            return IdentityAnalysis("",None,None)
    engine=Blocking()
    runtime=IdentityRuntime(lambda:engine,0.03,0.03)
    await runtime.start()
    try:
        with pytest.raises(TimeoutError):await runtime.analyze(b"a",b"b")
        with pytest.raises(TimeoutError):await runtime.analyze(b"a",b"b")
        assert engine.calls==1
    finally:
        released.set()
        await asyncio.sleep(0.05)
    assert runtime.semaphore.locked() is False
