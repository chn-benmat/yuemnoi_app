# agent/executor.py
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

    async def run_pipeline(self, user_query: str):
        """
        [วิธีที่ 1] ฟังก์ชันแบบ Async Generator
        จะทำการ 'yield' ข้อมูลสถานะและผลลัพธ์ทีละคำออกไปแบบ Real-time
        """

        # STEP 1: ค้นข้อมูลในระบบยืมหน่อยก่อนเสมอ
        yield f"data: {json.dumps({'status': 'searching_db', 'message': 'กำลังค้นหาอุปกรณ์ในระบบ yuemnoi...'})}\n\n"
        await asyncio.sleep(0.1)  # ปล่อยจังหวะให้ Event Loop ทำงาน

        try:
            db_results = self.db_tool.query_items(user_query)
        except Exception as e:
            db_results = []
            yield f"data: {json.dumps({'status': 'error', 'message': f'DB Error: {str(e)}'})}\n\n"

        # STEP 2: [วิธีที่ 3] ตรวจเช็คผ่านสมานสมองส่วน Router ว่าต้องรัน Google ไหม
        needs_google = self.router.check_needs_google_verification(user_query)
        google_context = ""

        if needs_google and db_results:
            # แจ้งสถานะอัปเดตหน้าจอแอปทันทีว่ากำลังตรวจสอบ Google สเปคเชิงลึกอยู่
            yield f"data: {json.dumps({'status': 'checking_google', 'message': f'พบไอเทม {len(db_results)} รายการ กำลังรีเช็คสเปคจริงกับ Google เพื่อความแม่นยำ...'})}\n\n"

            # ดึงชื่อไอเทมตัวแรกที่เจอมาเสิร์ชเพื่อเอาสเปคจริงมาชน
            target_item = db_results[0].get("item_name", "")
            google_context = self.google_tool.search_spec(target_item, user_query)
        else:
            # หากคำถามง่ายๆ ให้ข้ามเพื่อลดระยะเวลารอคอยของผู้ใช้ทันที
            yield f"data: {json.dumps({'status': 'skipping_google', 'message': 'สแกนคำถามแล้ว ข้อมูลพร้อมสรุปทันที...'})}\n\n"

        # STEP 3: ส่งข้อมูลประกอบร่างเข้าสู่ Prompt ประมวลผลสุดท้าย
        yield f"data: {json.dumps({'status': 'generating', 'message': 'กำลังเรียบเรียงคำตอบให้คุณ...'})}\n\n"

        final_prompt = f"""
        คุณคือ AI ประจำแอปพลิเคชัน 'yuemnoi' (แพลตฟอร์มเช่า-ยืมอุปกรณ์) 
        หน้าที่ของคุณคือการวิเคราะห์ข้อมูลอุปกรณ์ที่ค้นพบในระบบของเรา ผสมผสานกับสเปคทางการภายนอกจาก Google 
        แล้วตอบคำถามผู้ใช้อย่างซื่อสัตย์ เป็นมืออาชีพ หากพบว่าสเปคขัดแย้งกัน หรืออุปกรณ์ในแอปเราไม่ตรงตามต้องการ ให้เตือนตรงๆ ห้ามอวยเด็ดขาด
        
        ข้อมูลจากระบบ yuemnoi: {json.dumps(db_results, ensure_ascii=False)}
        ข้อมูลสเปคอ้างอิงจาก Google: {google_context}
        คำถามจากผู้ใช้งานแอป: {user_query}
        """

        # ทำการส่ง Prompt ยิงตรงหา Qwen แบบขอรับเอาต์พุตคืนรูปแบบ Stream
        async with httpx.AsyncClient() as client:
            async with client.stream(
                "POST",
                f"{settings.VLLM_ENDPOINT}/chat/completions",
                json={
                    "model": settings.MODEL_NAME,
                    "messages": [{"role": "user", "content": final_prompt}],
                    "stream": True,  # เปิดโหมดส่งข้อมูลทีละคำพิมพ์ตัวอักษร
                    "temperature": 0.3,
                },
                timeout=30.0,
            ) as response:

                async for chunk in response.iter_lines():
                    if not chunk:
                        continue
                    # ขูดข้อมูล Token คำตอบออกจากโครงสร้างของ vLLM/OpenAI Format
                    if chunk.startswith("data: "):
                        data_str = chunk[6:]
                        if data_str.strip() == "[DONE]":
                            break

                        try:
                            data_json = json.loads(data_str)
                            token = data_json["choices"][0]["delta"].get("content", "")
                            if token:
                                # พ่นข้อมูลผลลัพธ์คำตอบข้อความดิบยิงกลับไปให้ Network Pipe ทันที
                                yield f"data: {json.dumps({'status': 'text', 'message': token}, ensure_ascii=False)}\n\n"
                        except Exception:
                            continue
