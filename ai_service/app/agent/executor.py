import json
import asyncio
import httpx
from config import settings
from .router import IntentRouter
from ..tools.database_tool import DatabaseTool
from ..tools.google_tool import GoogleTool


class AgentExecutor:
    def __init__(self):
        self.router = IntentRouter()
        self.db_tool = DatabaseTool()
        self.google_tool = GoogleTool()

    async def run_pipeline_non_stream(self, user_query: str) -> dict:
        # """
        # [เวอร์ชันดักจับคำถามนอกเรื่อง] เช็คเจตนาผู้ใช้ตั้งแต่ต้นทาง
        # หากไม่เกี่ยวกับการเช่า/ยืมอุปกรณ์ ให้ปฏิเสธทันทีโดยไม่ต้องคิวรีฐานข้อมูล
        # """

        cleaned_query = user_query.strip()
        if len(cleaned_query) > 200:
            return {
                "status": "failed",
                "search_status": "skipping_google",
                "items_found": 0,
                "answer": "กรุณาพิมพ์คำถามให้กระชับและสั้นลงไม่เกิน 200 ตัวอักษรด้วยค่ะ",
                "recommended_items": [],
            }

        lowered_query = user_query.strip().lower()
        general_queries = [
            "ทำไรได้บ้าง",
            "ทำอะไรได้บ้าง",
            "แกคือใคร",
            "ช่วยอะไรได้",
            "สวัสดี",
        ]

        if lowered_query in general_queries or len(lowered_query) < 3:
            return {
                "status": "success",
                "search_status": "skipping_google",
                "items_found": 0,
                "answer": "กรุณาถามเกี่ยวกับอุปกรณ์ที่จะเช่าด้วยค่ะ",
                "recommended_items": [],
            }

        # ค้นข้อมูลในระบบ Yuemnoi ก่อนเสมอ
        try:
            db_results = self.db_tool.query_items(user_query)
        except Exception as e:
            print(f"[DB Error]: {str(e)}")
            db_results = []

        # ตรวจเช็คผ่าน Router ว่าต้องรัน Google ไหม
        needs_google = self.router.check_needs_google_verification(user_query)
        google_context = ""

        if needs_google and db_results:
            target_item = db_results[0].get("item_name", "")
            google_context = self.google_tool.search_spec(target_item, user_query)

        # Prompt สำหรับประมวลผลคำตอบ
        final_prompt = f"""
        คุณคือ AI ผู้ช่วยอัจฉริยะประจำแอปพลิเคชัน 'yuemnoi' (แพลตฟอร์มเช่าและยืมอุปกรณ์เท่านั้น ห้ามซื้อขายเด็ดขาด!) 
        หน้าที่ของคุณคือ: สวมบทบาทเป็นคอลเซ็นเตอร์ตอบคำถามของลูกค้าที่ทักเข้ามาถามเรื่องอุปกรณ์ โดยใช้ข้อมูลที่เราค้นหามาให้
        
        [ข้อมูลจริงในระบบ yuemnoi]: {json.dumps(db_results, ensure_ascii=False)}
        [ข้อมูลสเปคอ้างอิงจาก Google]: {google_context}
        [คำถามจากลูกค้า]: {user_query}
        
        **กฎเหล็กในการตอบ (Strict Rules - หากฝ่าฝืนโค้ดจะทำงานผิดพลาด):**
        1. ให้สวมบทบาทคุยกับลูกค้าโดยตรง "ทันที" ด้วยภาษาสุภาพ เป็นมิตร มีหางเสียง (ค่ะ/ครับ) และดูเป็นมืออาชีพ
        2. ห้ามเกริ่นนำอธิบายระบบหรือใช้คำพูดเชิงโปรแกรมเมอร์เด็ดขาด เช่น ห้ามพูดว่า "ตามข้อมูลที่คุณให้มา...", "จากระบบยืมหน่อย...", "คำตอบสำหรับผู้ใช้งานจะเป็นดังนี้"
        3. ห้ามใส่เครื่องหมายอัญประกาศคู่ ("...") หรือเครื่องหมายคำพูดครอบคำตอบเด็ดขาด ให้พ่นข้อความคำตอบออกมาตรงๆ ม้วนเดียวจบ
        4. หากพบอุปกรณ์ที่ตรงเงื่อนไข ให้สรุปกระชับว่ามีอะไรบ้าง ราคาค่าเช่าเท่าไหร่ และสถานะว่างไหม
        5. ย้ำ! แพลตฟอร์มนี้คือการ "เช่า-ยืม" ห้ามใช้คำว่า "ขาย" หรือ "พร้อมขาย" เด็ดขาด ให้ใช้คำว่า "ค่าเช่าต่อวัน" หรือ "ราคาเช่า" หรือ "ค่าเช่าต่อสัปดาห์" เท่านั้น
        6. กฎข้อบังคับภาษา: ต้องตอบเป็น "ภาษาไทย" ล้วนเท่านั้น ห้ามใส่คำศัพท์ภาษาจีน (เช่น 可供选择) หรือภาษาอื่นที่ไม่ใช่ภาษาไทยปนมาในคำตอบเด็ดขาด!
        7. การคัดกรองเนื้อหา (Out of Scope): หากคำถามของลูกค้า "ไม่เกี่ยวข้อง" กับการเช่า อุปกรณ์ หรือสิ่งของในระบบเลย (เช่น ถามเรื่องอาหาร, สภาพอากาศ, ข่าวบันเทิง หรือทักทายเล่นๆ ไร้สาระ) 
            ให้ตอบกลับลูกค้าด้วยประโยคนี้ประโยคเดียวเท่านั้น: "กรุณาถามเกี่ยวกับอุปกรณ์ที่จะเช่าด้วยคะ" ห้ามตอบเรื่องอื่นเด็ดขาด!
        """

        # เรียกประมวลผลข้อความแชทจาก LLM
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{settings.VLLM_ENDPOINT}/chat/completions",
                    json={
                        "model": settings.MODEL_NAME,
                        "messages": [{"role": "user", "content": final_prompt}],
                        "stream": False,
                        "temperature": 0.0,
                    },
                    timeout=45.0,
                )
                res_data = response.json()

                if "choices" in res_data and len(res_data["choices"]) > 0:
                    ai_answer = (
                        res_data["choices"][0]["message"].get("content", "").strip()
                    )
                else:
                    ai_answer = res_data.get("message", {}).get("content", "").strip()

            except Exception as e:
                ai_answer = f"ระบบเกิดข้อผิดพลาดในการประมวลผลกับตัวโมเดล: {str(e)}"

        #  แปลงผลลัพธ์ DB ออกเป็นโครงสร้าง
        recommended_items = []
        if db_results and isinstance(db_results, list):
            for item in db_results[
                :3
            ]:  # จำกัดสูงสุด 3 รายการเพื่อความสะอาดของหน้าจอแชท

                db_type = str(item.get("type", "")).strip()
                unit = "วัน"  # ค่าเริ่มต้นกรณีระบบตรวจจับไม่เจอคีย์เวิร์ด

                if "สัปดาห์" in db_type or "week" in db_type.lower():
                    unit = "สัปดาห์"
                elif "วัน" in db_type or "day" in db_type.lower():
                    unit = "วัน"

                # จัดการดึงลิงก์รูปภาพตัวแรกออกจากอาเรย์ text[] ของ Supabase
                image_array = item.get("item_image_url")
                cover_image = "https://placeholder.com/image.png"  # กรณีไม่มีรูปในระบบ

                if (
                    image_array
                    and isinstance(image_array, list)
                    and len(image_array) > 0
                ):
                    cover_image = image_array[0]
                elif isinstance(image_array, str):
                    cover_image = image_array

                # ประกอบร่างโครงสร้างข้อมูลคลีนๆ ส่งกลับไป
                recommended_items.append(
                    {
                        "id": item.get("id"),
                        "item_name": item.get("item_name"),
                        "price": item.get("price"),
                        "price_display": f"{item.get('price')}/{unit}",
                        "unit": unit,
                        "image_url": cover_image,
                        "status": item.get("status"),
                        "category": item.get("category"),
                        "description": item.get("description"),
                    }
                )

        # ส่ง JSON
        return {
            "status": "success",
            "search_status": (
                "skipping_google" if not google_context else "checked_google"
            ),
            "items_found": len(db_results),
            "answer": ai_answer,
            "recommended_items": recommended_items,  # ข้อมูลดิบสำหรับเรนเดอร์ Widget การ์ดรูปภาพ + ปุ่มกดปล่อยเช่าสีม่วง
        }
