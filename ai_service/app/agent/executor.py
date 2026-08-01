import json
import httpx
from config import settings
from ..tools.database_tool import DatabaseTool
from ..tools.google_tool import GoogleTool
from typing import List, Optional


class AgentExecutor:
    def __init__(self):
        self.db_tool = DatabaseTool()
        self.google_tool = GoogleTool()

    async def _get_reference_context(
        self, cleaned_query: str, db_results: list
    ) -> tuple[str, str]:
        if db_results:
            return "", "using_supabase"

        return await self.google_tool.search_spec(specific_query=cleaned_query)

    async def run_pipeline_non_stream(
        self, user_query: str, history: Optional[List[dict]] = None
    ) -> dict:

        cleaned_query = user_query.strip()

        #  ตรวจสอบความยาวตัวอักษร
        if len(cleaned_query) > 200:
            return {
                "status": "failed",
                "search_status": "skipping_google",
                "items_found": 0,
                "answer": "กรุณาพิมพ์คำถามให้กระชับและสั้นลง เพื่อความรวดเร็วในการบริการค่ะ",
                "recommended_items": [],
            }

        # ตรวจจับและปฏิเสธคำถามทั่วไปหรือนอกเรื่องธุรกิจยืมหน่อย
        lowered_query = cleaned_query.lower()
        general_queries = [
            "ทำไรได้บ้าง",
            "ทำอะไรได้บ้าง",
            "ช่วยอะไรได้บ้าง",
            "แกคือใคร",
            "คุณคือใคร",
            "สวัสดี",
        ]
        business_keywords = [
            "เช่า",
            "ยืม",
            "กล้อง",
            "เลนส์",
            "อุปกรณ์",
            "มีไหม",
            "ตัวไหนว่าง",
            "ราคา",
            "บาท",
            "วัน",
            "สัปดาห์",
        ]

        is_general = lowered_query in general_queries
        has_business_word = any(word in lowered_query for word in business_keywords)

        if is_general or (not has_business_word and len(lowered_query) < 3):
            return {
                "status": "success",
                "search_status": "skipping_google",
                "items_found": 0,
                "answer": "กรุณาสอบถามเกี่ยวกับอุปกรณ์ที่ต้องการเช่าในระบบนะคะ",
                "recommended_items": [],
            }

        # ค้นข้อมูลในระบบ Yuemnoi ก่อนเสมอ
        try:
            db_results = self.db_tool.query_items(cleaned_query)
        except Exception as e:
            print(f"[DB Error]: {str(e)}")
            db_results = []

        # ใช้ข้อมูล Supabase เป็นหลัก และค้น Google เฉพาะเมื่อไม่พบข้อมูลในฐานข้อมูล
        google_context, search_status = await self._get_reference_context(
            cleaned_query=cleaned_query,
            db_results=db_results,
        )

        # ตรรกะแปลงประวัติการแชท (Chat History Loop)
        formatted_history = ""
        if history:
            for message in history:
                role = (
                    "ลูกค้า (User)"
                    if message.get("role") == "user"
                    else "AI ผู้ช่วยยืมหน่อย (Assistant)"
                )
                formatted_history += f"{role}: {message.get('content')}\n"
        else:
            formatted_history = "ไม่มีประวัติการสนทนาก่อนหน้านี้\n"

        #  Prompt บังคับให้ Qwen ส่งกลับเป็นโครงสร้าง JSON
        final_prompt = f"""
        คุณคือ AI ผู้ช่วยอัจฉริยะประจำแอปพลิเคชัน 'yuemnoi' (แพลตฟอร์มเช่าและยืมอุปกรณ์เท่านั้น ห้ามซื้อขายเด็ดขาด!) 
        หน้าที่ของคุณคือวิเคราะห์ข้อมูลในระบบและประวัติการคุย แล้วตอบกลับในรูปแบบ JSON Object ที่กำหนดไว้เท่านั้น
        
        [ประวัติการสนทนาก่อนหน้านี้]:
        {formatted_history}

        [ข้อมูลจริงปัจจุบันในระบบ yuemnoi]: {json.dumps(db_results, ensure_ascii=False)}
        [ข้อมูลสเปคอ้างอิงจาก Google]: {google_context}
        [คำถามล่าสุดจากลูกค้า]: {cleaned_query}
        
        **กฎเหล็กสำนวนการตอบเพื่อลูกค้า:**
        1. สวมบทบาทเป็นผู้หญิงสุภาพ อบอุ่น นุ่มนวล ลงท้ายด้วย "ค่ะ" หรือ "คะ" ให้ถูกต้องตามหลักภาษาไทยเสมอ (ห้ามใช้คำว่า "ครับ")
        2. อ่านประวัติและเลือกตอบเฉพาะอุปกรณ์ในคลังระบบที่ตรงความต้องการของลูกค้าที่สุดเพียงชิ้นเดียวหรือตามที่คุยค้างไว้ ห้ามใช้คำว่า "ขาย"
        3. ตอบกลับเป็นรูปแบบ JSON โครงสร้างนี้เท่านั้น ห้ามเกริ่นนำภาษาคนนอกก้อน JSON เด็ดขาด: {{ "answer": "ข้อความแชทสุภาพที่คุยกับลูกค้า", "selected_item_id": ไอดีของสินค้าในคลังที่คุณเลือกตอบ (ระบุเป็นตัวเลข bigint หรือ null หากไม่เจอชิ้นที่ตรงเงื่อนไขเลย) }}
        4. หากมีข้อมูลจากระบบ yuemnoi ให้ใช้ข้อมูลนั้นเป็นแหล่งหลักและห้ามอ้างว่าได้ตรวจสอบจาก Google
        5. หากไม่มีข้อมูลจากระบบและมีข้อมูลจาก Google ให้ตรวจสอบอย่างน้อย 2 แหล่งก่อนนำมาอ้างอิง ให้ความสำคัญกับเว็บไซต์ผู้ผลิตหรือแหล่งข้อมูลทางการ หากแหล่งข้อมูลไม่ตรงกันหรือมีไม่ถึง 2 แหล่ง ให้แจ้งลูกค้าว่ายังยืนยันข้อมูลนั้นไม่ได้ ห้ามแต่งข้อมูลที่ไม่มีในแหล่งอ้างอิง
        """

        ai_answer = "ขออภัยค่ะ ระบบเกิดข้อผิดพลาดในการประมวลผลข้อความชั่วคราว"
        selected_id = None

        # เรียกประมวลผลข้อความแชทจาก LLM
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{settings.OLLAMA_ENDPOINT}/chat/completions",
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
                    raw_content = (
                        res_data["choices"][0]["message"].get("content", "").strip()
                    )
                else:
                    raw_content = res_data.get("message", {}).get("content", "").strip()

                # แกะโครงสร้าง JSON
                if raw_content:
                    # ป้องกันกรณีบอทเผลอพ่น Markdown ครอบ JSON มา
                    if "```" in raw_content:
                        raw_content = (
                            raw_content.split("```")[1].replace("json", "").strip()
                        )

                    parsed_json = json.loads(raw_content)
                    ai_answer = parsed_json.get("answer", "").strip()
                    selected_id = parsed_json.get("selected_item_id")

            except Exception as e:
                print(f"[LLM JSON Parse Error]: {str(e)}")
                # Fallback กรณีแปลง JSON พัง ให้ใช้ข้อความดิบ
                if "raw_content" in locals() and raw_content and "{" not in raw_content:
                    ai_answer = raw_content

        # กรองไอเทมหน้าบ้านให้ตรงเฉพาะชิ้นที่ AI เลือกคุยกับลูกค้าเท่านั้น!
        recommended_items = []
        if db_results and isinstance(db_results, list):
            for item in db_results:
                item_id = item.get("id")

                # ถ้า AI ระบุไอดีเจาะจงมา ให้เลือกการ์ดเฉพาะไอดีนั้น! แต่ถ้า AI หาไม่เจอ ให้ปล่อยโชว์ทั้งหมดไปก่อน
                if selected_id is not None and item_id != selected_id:
                    continue

                db_type = str(item.get("type", "")).strip()
                unit = "วัน"

                if "สัปดาห์" in db_type or "week" in db_type.lower():
                    unit = "สัปดาห์"
                elif "วัน" in db_type or "day" in db_type.lower():
                    unit = "วัน"

                image_array = item.get("item_image_url")
                cover_image = "https://placeholder.com/image.png"

                if (
                    image_array
                    and isinstance(image_array, list)
                    and len(image_array) > 0
                ):
                    cover_image = image_array[0]
                elif isinstance(image_array, str):
                    cover_image = image_array

                recommended_items.append(
                    {
                        "id": item_id,
                        "item_name": item.get("item_name"),
                        "price": item.get("price"),
                        "unit": unit,
                        "image_url": cover_image,
                        "status": item.get("status", "available"),
                        "category": item.get("category"),
                        "description": item.get("description"),
                    }
                )

        # ส่ง JSON
        return {
            "status": "success",
            "search_status": search_status,
            "items_found": len(recommended_items),
            "answer": ai_answer,
            "recommended_items": recommended_items,
        }
