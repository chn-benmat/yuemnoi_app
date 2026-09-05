"""เลือกบริบทจากคำถามผู้ใช้ โดยไม่ให้คำตอบเก่ากลายเป็นเงื่อนไขค้นหา"""
import re
from dataclasses import dataclass


KINDS = {
    "camera": ("กล้อง", "ถ่ายภาพ", "ถ่ายรูป", "camera"),
    "camping": ("แคมป์", "camping", "เดินป่า"),
    "tent": ("เต็นท์", "tent"),
    "tripod": ("ขาตั้งกล้อง", "tripod"),
    "camera_bag": ("กระเป๋ากล้อง", "camera bag"),
    "lens": ("เลนส์", "lens"),
    "drone": ("โดรน", "drone"),
    "speaker": ("ลำโพง", "speaker"),
    "microphone": ("ไมค์", "ไมโครโฟน", "microphone"),
    "bike": ("จักรยาน", "bicycle"),
    "house": ("บ้านพัก", "บ้าน", "พูลวิลล่า", "villa"),
    "drill": ("สว่าน", "drill"),
}


def normalize(text: str) -> str:
    return text.strip().replace("อุปกณ์", "อุปกรณ์").replace("ออกแคม", "แคมป์ปิ้ง").replace("เต้นท์", "เต็นท์")


def kinds(text: str) -> set[str]:
    text = normalize(text).casefold()
    return {kind for kind, terms in KINDS.items() if any(term in text for term in terms)}


@dataclass(frozen=True)
class ConversationContext:
    original: str
    query: str
    history: list[dict]
    clarification: bool = False
    clarification_kind: str = "activity"


def resolve(query: str, history: list[dict] | None) -> ConversationContext:
    current = normalize(query)
    q = re.sub(r"(?:ครับ|ค่ะ|คะ)[!? ]*$", "", current.casefold()).strip()
    generic = q.rstrip("?!？ ") in {
        "แนะนำอุปกรณ์หน่อย", "ช่วยแนะนำอุปกรณ์หน่อย", "แนะนำของหน่อย",
        "แนะนำหน่อย", "recommend equipment", "recommend something",
    }
    followup = bool(re.search(r"(?:เอา|ขอ|only)\s*\d+\s*(?:ตัว|ชิ้น|รายการ|items?)", q)) or any(term in q for term in (
        "กว่านี้", "ตัวนี้", "อันนี้", "ตัวเดิม", "เอาตัวเดียว", "เอาอันเดียว",
        "cheaper", "this one", "that one", "only one", "งบ", "ไม่เกิน", "ราคาเท่าไหร่", "กี่บาท", "how much",
    ))
    # ประเภทใหม่ต้องไม่รับเงื่อนไขจากข้อความก่อนหน้า
    activity = any(term in q for term in ("คอนเสิร์ต", "ทำคลิป", "จัดงาน", "vlog", "concert", "party"))
    current_kinds = kinds(current)
    previous_kinds = next((kinds(str(message.get("content") or "")) for message in reversed(history or []) if message.get("role") == "user" and kinds(str(message.get("content") or ""))), set())
    same_topic = followup and current_kinds == previous_kinds and bool(current_kinds)
    if (current_kinds and not same_topic) or activity or generic or not followup:
        return ConversationContext(query, current, [], generic)
    selected = []
    for message in reversed((history or [])[-6:]):
        if message.get("role") != "user":
            continue
        previous = normalize(str(message.get("content") or ""))[:200]
        if previous.casefold() in {"แนะนำอุปกรณ์หน่อย", "ทำไรได้บ้าง", "ทำอะไรได้บ้าง"}:
            break
        selected.append(previous)
        if kinds(previous):
            break
    if not selected or not kinds(selected[-1]):
        return ConversationContext(query, current, [], True)
    # งบใหม่แทนงบเก่า ไม่ส่งตัวเลขเก่าให้ matcher ตีความซ้ำ
    if re.search(r"\d", current) and any(word in q for word in ("งบ", "ราคา", "บาท", "thb", "under", "ไม่เกิน")):
        selected = [re.sub(r"(?:(?:งบ(?:ประมาณ)?|ราคา|under)\s*(?:ไม่เกิน|ต่ำกว่า)?\s*[\d,]+(?:\.\d+)?\s*(?:บาท|thb)?|(?:ไม่เกิน|ต่ำกว่า)\s*[\d,]+(?:\.\d+)?(?![\d.,]|\s*(?:วัน|เดือน|คน))\s*(?:บาท|thb)?|[\d,]+(?:\.\d+)?\s*(?:บาท|thb))", "", text, flags=re.I) for text in selected]
    scoped = [{"role": "user", "content": text} for text in reversed(selected)]
    if any(term in q for term in ("ตัวนี้", "อันนี้", "this one", "that one")):
        previous_answer = next((str(message.get("content") or "") for message in reversed(history or []) if message.get("role") == "assistant"), "")
        names = re.findall(r"•\s*\*\*([^*]+)\*\*", previous_answer)
        if len(names) != 1:
            return ConversationContext(query, current, [], True, "item")
        # เก็บเฉพาะชื่อที่ผู้ใช้กำลังอ้างถึง ไม่ยกคำตอบเก่าทั้งชุดเป็นเงื่อนไข
        scoped.append({"role": "assistant", "content": names[0][:100]})
    if any(term in q for term in ("ถูกกว่านี้", "cheaper")):
        for message in reversed(history or []):
            if message.get("role") == "assistant":
                text = str(message.get("content") or "").replace("*", "")
                prices = re.findall(r"([\d,]+(?:\.\d+)?)\s*(?:บาท|THB)", text, re.I)
                if prices:
                    maximum = min(float(price.replace(",", "")) for price in prices) - .01
                    current += f" ไม่เกิน {maximum:.2f} บาท" if any("ก" <= c <= "๛" for c in query) else f" under {maximum:.2f} THB"
                else:
                    return ConversationContext(query, current, [], True)
                break
    return ConversationContext(query, current, scoped)
