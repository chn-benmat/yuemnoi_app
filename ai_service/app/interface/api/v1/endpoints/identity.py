import asyncio
import hmac
from fastapi import APIRouter, File, UploadFile
from fastapi.responses import JSONResponse
from app.core.config import settings
from app.core.identity_settings import identity_settings as config
from app.application.identity import IdentityRuntime
from app.infrastructure.identity.engine import VisionIdentityEngine

router=APIRouter(prefix="/identity")
runtime=IdentityRuntime(lambda:VisionIdentityEngine(config),config.IDENTITY_TIMEOUT_SECONDS,config.IDENTITY_QUEUE_TIMEOUT_SECONDS)

class IdentityProtection:
    def __init__(self,app): self.app=app
    async def __call__(self,scope,receive,send):
        if scope["type"]!="http" or not scope.get("path","").startswith("/api/identity"):
            return await self.app(scope,receive,send)
        headers=dict(scope.get("headers",[]))
        key=settings.INTERNAL_SERVICE_KEY.split(",")[0].strip().encode()
        if not key or not hmac.compare_digest(headers.get(b"x-internal-service-key",b""),key):
            return await JSONResponse({"error":"unauthorized"},status_code=401)(scope,receive,send)
        if not config.IDENTITY_ENABLED:
            return await JSONResponse({"error":"identity_unavailable"},status_code=503)(scope,receive,send)
        try: length=int(headers.get(b"content-length",b"0"))
        except ValueError: length=config.IDENTITY_REQUEST_BYTES+1
        if length>config.IDENTITY_REQUEST_BYTES:
            return await JSONResponse({"error":"request_too_large"},status_code=413)(scope,receive,send)
        received=0
        async def limited():
            nonlocal received
            message=await receive();received+=len(message.get("body",b""))
            if received>config.IDENTITY_REQUEST_BYTES: raise ValueError("request_too_large")
            return message
        await self.app(scope,limited,send)

@router.get("/health")
async def health():
    return JSONResponse({"ready":runtime.engine is not None},status_code=200 if runtime.engine is not None else 503,
                        headers={"Cache-Control":"no-store"})

@router.post("/analyze")
async def analyze(card:UploadFile=File(...),selfie:UploadFile=File(...)):
    try:
        a,b=await card.read(config.IDENTITY_MAX_BYTES+1),await selfie.read(config.IDENTITY_MAX_BYTES+1)
        if len(a)>config.IDENTITY_MAX_BYTES or len(b)>config.IDENTITY_MAX_BYTES:
            return JSONResponse({"error":"invalid_image"},status_code=413)
        result=await runtime.analyze(a,b)
        return JSONResponse(result.to_dict(),headers={"Cache-Control":"no-store"})
    except ValueError:
        return JSONResponse({"error":"invalid_image"},status_code=400)
    except (TimeoutError,asyncio.TimeoutError):
        return JSONResponse({"error":"identity_busy"},status_code=503)
    except Exception:
        return JSONResponse({"error":"identity_unavailable"},status_code=503)
    finally:
        await card.close();await selfie.close()

@router.post("/read-card")
async def read_card(card:UploadFile=File(...)):
    try:
        data=await card.read(config.IDENTITY_MAX_BYTES+1)
        if len(data)>config.IDENTITY_MAX_BYTES:
            return JSONResponse({"error":"invalid_image"},status_code=413)
        result=await runtime.read_card(data)
        return JSONResponse(result,headers={"Cache-Control":"no-store"})
    except ValueError:
        return JSONResponse({"error":"invalid_image"},status_code=400)
    except (TimeoutError,asyncio.TimeoutError):
        return JSONResponse({"error":"identity_busy"},status_code=503)
    except Exception:
        return JSONResponse({"error":"identity_unavailable"},status_code=503)
    finally:
        await card.close()
