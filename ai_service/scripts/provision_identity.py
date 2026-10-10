"""เรียกจาก ai_service: python scripts/provision_identity.py แล้ว commit manifest ที่ได้"""
import asyncio
import hashlib
import json
from pathlib import Path
import httpx

ROOT=Path(__file__).resolve().parents[1]
SILENT="b6d5f04ad78778917853b25c778acef6d5626d15"
ZOO="47534e27c9851bb1128ccc0102f1145e27f23f98"
ARTIFACTS={
 "models/yunet.onnx":f"https://media.githubusercontent.com/media/opencv/opencv_zoo/{ZOO}/models/face_detection_yunet/face_detection_yunet_2023mar.onnx",
 "models/sface.onnx":f"https://media.githubusercontent.com/media/opencv/opencv_zoo/{ZOO}/models/face_recognition_sface/face_recognition_sface_2021dec.onnx",
 "vendor/silent_face/MiniFASNet.py":f"https://raw.githubusercontent.com/minivision-ai/Silent-Face-Anti-Spoofing/{SILENT}/src/model_lib/MiniFASNet.py",
 "vendor/silent_face/LICENSE":f"https://raw.githubusercontent.com/minivision-ai/Silent-Face-Anti-Spoofing/{SILENT}/LICENSE",
 "models/minifas_v2.pth":f"https://raw.githubusercontent.com/minivision-ai/Silent-Face-Anti-Spoofing/{SILENT}/resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.pth",
 "models/minifas_v1se.pth":f"https://raw.githubusercontent.com/minivision-ai/Silent-Face-Anti-Spoofing/{SILENT}/resources/anti_spoof_models/4_0_0_80x80_MiniFASNetV1SE.pth",
 "models/LICENSE-yunet":f"https://raw.githubusercontent.com/opencv/opencv_zoo/{ZOO}/models/face_detection_yunet/LICENSE",
 "models/LICENSE-sface":f"https://raw.githubusercontent.com/opencv/opencv_zoo/{ZOO}/models/face_recognition_sface/LICENSE",
}

async def main():
    manifest_path=ROOT/"config/identity_models.json"
    previous=json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    expected={entry["path"]:entry["sha256"] for entry in previous.get("files",[])}
    async with httpx.AsyncClient(timeout=180,follow_redirects=True) as client:
        for relative,url in ARTIFACTS.items():
            path=ROOT/relative;path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists():
                response=await client.get(url);response.raise_for_status()
                path.write_bytes(response.content)
            digest=hashlib.sha256(path.read_bytes()).hexdigest()
            if relative in expected and digest!=expected[relative]: raise RuntimeError("model_hash_mismatch: "+relative)
    def ocr():
        import easyocr
        easyocr.Reader(["th","en"],gpu=False,model_storage_directory=str(ROOT/"models/easyocr"),verbose=False,download_enabled=True)
    await asyncio.to_thread(ocr)
    files=[]
    for relative,url in ARTIFACTS.items():
        files.append({"path":relative,"sha256":hashlib.sha256((ROOT/relative).read_bytes()).hexdigest(),"source":url})
    for path in (ROOT/"models/easyocr").glob("*.pth"):
        relative=path.relative_to(ROOT).as_posix();digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if relative in expected and digest!=expected[relative]: raise RuntimeError("ocr_hash_mismatch")
        files.append({"path":relative,"sha256":digest,"source":"https://github.com/JaidedAI/EasyOCR/releases"})
    manifest={
        "versions":{"easyocr":"1.7.2","sface":"opencv_zoo@"+ZOO,"yunet":"2023mar","silent_face":SILENT},
        "files":files,"yunet":"models/yunet.onnx","sface":"models/sface.onnx","ocr_directory":"models/easyocr",
        "minifas_source":"vendor/silent_face/MiniFASNet.py",
        "spoof":[{"path":"models/minifas_v2.pth","architecture":"MiniFASNetV2","scale":2.7},
                 {"path":"models/minifas_v1se.pth","architecture":"MiniFASNetV1SE","scale":4.0}],
    }
    manifest_path.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print("Identity models provisioned and SHA-256 manifest verified")

if __name__=="__main__": asyncio.run(main())
