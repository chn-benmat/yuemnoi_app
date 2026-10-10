import hashlib
import importlib.util
import io
import json
from pathlib import Path
import threading

from app.core.identity_settings import IdentitySettings
from app.domain.identity import IdentityAnalysis

class VisionIdentityEngine:
    """โมเดลทำงานในหน่วยความจำและคืนคะแนนประกอบการตรวจโดยคนเท่านั้น"""
    def __init__(self, settings: IdentitySettings):
        import cv2
        import easyocr
        import torch
        self.cv, self.torch, self.settings = cv2, torch, settings
        torch.set_num_threads(settings.IDENTITY_TORCH_THREADS)
        manifest = json.loads(settings.IDENTITY_MANIFEST.read_text(encoding="utf-8"))
        for entry in manifest["files"]:
            path = Path(entry["path"])
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
                raise RuntimeError("identity_model_integrity")
        self.versions = manifest["versions"]
        self.detector = cv2.FaceDetectorYN.create(manifest["yunet"], "", (320,320),
            settings.IDENTITY_FACE_CONFIDENCE, settings.IDENTITY_FACE_NMS, settings.IDENTITY_FACE_TOP_K)
        self.recognizer = cv2.FaceRecognizerSF.create(manifest["sface"], "")
        self.reader = easyocr.Reader(["th","en"], gpu=False, model_storage_directory=manifest["ocr_directory"],
                                    download_enabled=False, verbose=False)
        spec = importlib.util.spec_from_file_location("yuemnoi_minifasnet", manifest["minifas_source"])
        if spec is None or spec.loader is None:
            raise RuntimeError("identity_model_source")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.spoof_models = []
        for entry in manifest["spoof"]:
            model = getattr(module, entry["architecture"])(conv6_kernel=(5,5))
            weights = torch.load(entry["path"], map_location="cpu", weights_only=True)
            weights = {k.removeprefix("module."): v for k,v in weights.items()}
            model.load_state_dict(weights)
            self.spoof_models.append((model.eval(),entry["scale"]))
        self.lock = threading.Lock()

    def decode(self, data: bytes):
        import numpy as np
        from PIL import Image, ImageOps
        if not data or len(data)>self.settings.IDENTITY_MAX_BYTES:
            raise ValueError("invalid_image")
        with Image.open(io.BytesIO(data)) as image:
            if image.format not in ("JPEG","PNG") or image.width*image.height>self.settings.IDENTITY_MAX_PIXELS:
                raise ValueError("invalid_image")
            image = ImageOps.exif_transpose(image).convert("RGB")
            return self.cv.cvtColor(np.asarray(image),self.cv.COLOR_RGB2BGR)

    def faces(self, image):
        h,w = image.shape[:2]
        self.detector.setInputSize((w,h))
        _,faces = self.detector.detect(image)
        return [] if faces is None else faces

    def live(self, image, face) -> float:
        import numpy as np
        h,w = image.shape[:2]
        x,y,bw,bh = map(float,face[:4])
        scores=[]
        for model,scale in self.spoof_models:
            scale=min(scale,(w-1)/bw,(h-1)/bh)
            cw,ch=bw*scale,bh*scale
            left=max(0,min(w-cw,x+bw/2-cw/2)); top=max(0,min(h-ch,y+bh/2-ch/2))
            crop=image[int(top):int(top+ch),int(left):int(left+cw)]
            if not crop.size: raise ValueError("invalid_face_crop")
            crop=self.cv.resize(crop,(80,80))
            # official Silent-Face ToTensor ใช้ BGR float 0..255 ไม่หาร 255
            tensor=self.torch.from_numpy(np.ascontiguousarray(crop.transpose(2,0,1))).float().unsqueeze(0)
            with self.torch.inference_mode():
                scores.append(float(self.torch.softmax(model(tensor),dim=1)[0,1].item()))
        return sum(scores)/len(scores)

    def read_card(self, card: bytes) -> dict:
        # ส่งผลตัวอักษรและตำแหน่งจาก OCR ให้ backend จัดรูปแบบ ไม่ส่งไปบริการภายนอก
        with self.lock:
            return self._read_card_image(self.decode(card))

    def _read_card_image(self, image) -> dict:
        height, width = image.shape[:2]
        config = self.settings

        def recognize(candidate):
            blocks = []
            readings = self.reader.readtext(
                candidate, detail=1, paragraph=False,
                decoder=config.IDENTITY_OCR_DECODER,
                beamWidth=config.IDENTITY_OCR_BEAM_WIDTH,
                canvas_size=config.IDENTITY_OCR_CANVAS_SIZE,
                mag_ratio=config.IDENTITY_OCR_MAG_RATIO,
                min_size=config.IDENTITY_OCR_MIN_SIZE,
                add_margin=config.IDENTITY_OCR_MARGIN,
                width_ths=config.IDENTITY_OCR_WIDTH_THRESHOLD,
                height_ths=config.IDENTITY_OCR_HEIGHT_THRESHOLD,
                contrast_ths=config.IDENTITY_OCR_CONTRAST_THRESHOLD,
            )
            for box, text, confidence in readings:
                xs, ys = [float(p[0]) for p in box], [float(p[1]) for p in box]
                blocks.append({"text": text, "confidence": float(confidence),
                    "x": min(xs)/width, "y": min(ys)/height,
                    "width": (max(xs)-min(xs))/width, "height": (max(ys)-min(ys))/height})
            return blocks

        result = {"blocks": recognize(image)}
        if config.IDENTITY_OCR_ENHANCE:
            gray = self.cv.cvtColor(image, self.cv.COLOR_BGR2GRAY)
            gray = self.cv.normalize(gray, None, 0, 255, self.cv.NORM_MINMAX)
            grid = config.IDENTITY_OCR_CLAHE_GRID
            enhanced = self.cv.createCLAHE(
                clipLimit=config.IDENTITY_OCR_CLAHE_CLIP, tileGridSize=(grid, grid),
            ).apply(gray)
            # แยกผลแต่ละรอบไว้ให้ backend ตรวจความขัดแย้ง ไม่ต่อข้อความซ้ำเป็นบรรทัดเดียว
            result["alternatives"] = [recognize(enhanced)]
        return result

    def analyze(self, card: bytes, selfie: bytes) -> IdentityAnalysis:
        with self.lock:
            card_img,face_img = self.decode(card),self.decode(selfie)
            reading = self._read_card_image(card_img)
            # แนบข้อความทั้งสองรอบเพื่อให้เจ้าหน้าที่ตรวจข้อมูลที่อ่านไม่ตรงกัน
            texts = dict.fromkeys(block["text"] for blocks in
                [reading["blocks"], *reading.get("alternatives", [])] for block in blocks)
            text = "\n".join(texts)
            card_faces, selfie_faces = self.faces(card_img),self.faces(face_img)
            warnings=["คะแนนโมเดลยังไม่ได้สอบเทียบกับผู้ใช้จริง ห้ามใช้อนุมัติอัตโนมัติ",
                      "ภาพนิ่งไม่ยืนยันการมีชีวิตหรือความแท้ของบัตร ต้องตรวจโดยเจ้าหน้าที่"]
            similarity,live=None,None
            if len(card_faces)!=1: warnings.append("ภาพบัตรต้องเห็นใบหน้าหนึ่งคนชัดเจน")
            if len(selfie_faces)!=1: warnings.append("ภาพใบหน้าต้องเห็นหนึ่งคนชัดเจน")
            if len(card_faces)==1 and len(selfie_faces)==1:
                card_feature=self.recognizer.feature(self.recognizer.alignCrop(card_img,card_faces[0]))
                face_feature=self.recognizer.feature(self.recognizer.alignCrop(face_img,selfie_faces[0]))
                similarity=float(self.recognizer.match(card_feature,face_feature,self.cv.FaceRecognizerSF_FR_COSINE))
                live=self.live(face_img,selfie_faces[0])
            return IdentityAnalysis(text,similarity,live,warnings,self.versions)
