"""เปรียบเทียบ OCR ด้วยบัตรจำลองที่ไม่มีข้อมูลบุคคลจริงและไม่เรียกบริการภายนอก"""
import argparse
import io
import json
import time
import unicodedata
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from app.core.identity_settings import IdentitySettings
from app.infrastructure.identity.engine import VisionIdentityEngine


def synthetic_card(font_path: Path) -> Image.Image:
    image = Image.new("RGB", (1000, 630), "white")
    draw = ImageDraw.Draw(image)
    draw.rectangle((1, 1, 998, 628), outline=(110, 110, 110), width=3)
    draw.rectangle((40, 180, 230, 440), fill=(210, 210, 210))
    rows = [
        (30, 25, 28, "บัตรทดสอบระบบ ไม่มีข้อมูลบุคคลจริง"),
        (300, 85, 38, "0 0000 00000 00 1"),
        (270, 155, 30, "ชื่อตัวและชื่อสกุล นายทดสอบ"),
        (270, 205, 30, "นามสกุล ระบบ"),
        (270, 300, 30, "เกิดวันที่ 1 ม.ค. 2543"),
        (270, 350, 24, "Date of Birth 1 Jan. 2000"),
        (40, 515, 28, "1 ม.ค. 2565"),
        (580, 515, 28, "1 ม.ค. 2575"),
        (40, 558, 25, "วันออกบัตร"),
        (580, 558, 25, "วันบัตรหมดอายุ"),
    ]
    for x, y, size, text in rows:
        draw.text((x, y), text, fill=(20, 20, 20), font=ImageFont.truetype(str(font_path), size))
    return image


def normalized(text: str) -> str:
    return "".join(char for char in unicodedata.normalize("NFC", text) if char.isalnum())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    engine = VisionIdentityEngine(IdentitySettings())
    card = synthetic_card(args.font)
    low_contrast = card.point(lambda value: int(175 + value * 0.18))
    small = card.resize((650, 410), Image.Resampling.LANCZOS)
    cases = {"clean": card, "low_contrast": low_contrast, "small": small}
    expected_tokens = ["0000000000001", "นายทดสอบ", "ระบบ", "1มค2543", "1มค2575"]
    reports = []
    for name, image in cases.items():
        data = io.BytesIO()
        image.save(data, format="PNG")
        started = time.monotonic()
        baseline = engine.reader.readtext(engine.decode(data.getvalue()), detail=1, paragraph=False)
        baseline_seconds = time.monotonic() - started
        started = time.monotonic()
        improved = engine.read_card(data.getvalue())
        improved_seconds = time.monotonic() - started
        baseline_text = normalized(" ".join(text for _, text, _ in baseline))
        improved_text = normalized(" ".join(block["text"] for blocks in
            [improved["blocks"], *improved.get("alternatives", [])] for block in blocks))
        scores = {
            "case": name,
            "baseline_tokens": sum(token in baseline_text for token in expected_tokens),
            "improved_tokens": sum(token in improved_text for token in expected_tokens),
            "total_tokens": len(expected_tokens),
            "baseline_seconds": round(baseline_seconds, 2),
            "improved_seconds": round(improved_seconds, 2),
        }
        print(json.dumps(scores), flush=True)
        height, width = image.height, image.width
        baseline_blocks = []
        for box, text, confidence in baseline:
            xs, ys = [float(p[0]) for p in box], [float(p[1]) for p in box]
            baseline_blocks.append({"text": text, "confidence": float(confidence),
                "x": min(xs)/width, "y": min(ys)/height,
                "width": (max(xs)-min(xs))/width, "height": (max(ys)-min(ys))/height})
        reports.append({**scores, "models": engine.versions,
            "ocr_settings": {key: value for key, value in engine.settings.model_dump(mode="json").items()
                if key.startswith("IDENTITY_OCR_")},
            "baseline": {"blocks": baseline_blocks}, "ocr": improved})
    args.output.write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
