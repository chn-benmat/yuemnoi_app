# tools/google_tool.py
import httpx
from config import settings


class GoogleTool:
    def __init__(self):
        self.api_url = (
            "[https://google.serper.dev/search](https://google.serper.dev/search)"
        )
        self.headers = {
            "X-API-KEY": settings.SERPER_API_KEY,
            "Content-Type": "application/json",
        }

    def search_spec(self, item_name: str, specific_query: str) -> str:
        search_keyword = f"{item_name} official specs {specific_query}"

        payload = {
            "q": search_keyword,
            "gl": "th",  # โฟกัสผลลัพธ์ในประเทศไทย
            "hl": "th",  # ดึงเนื้อหาภาษาไทยเป็นหลัก
        }

        try:
            with httpx.Client() as client:
                response = client.post(
                    self.api_url, headers=self.headers, json=payload, timeout=10.0
                )
                if response.status_code == 200:
                    results = response.json()
                    # ดึงข้อมูลจาก Organic Search Snippets มารวมกัน 3 อันดับแรก เพื่อความกระชับ
                    snippets = [
                        item.get("snippet", "")
                        for item in results.get("organic", [])[:3]
                    ]
                    return "\n".join(snippets)
                return "ไม่สามารถค้นหาข้อมูลจาก Google ได้ในขณะนี้"
        except Exception as e:
            return f"เกิดข้อผิดพลาดในการเชื่อมต่อ Google: {str(e)}"
