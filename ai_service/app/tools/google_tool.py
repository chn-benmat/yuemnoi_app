# tools/google_tool.py
import httpx
from config import settings


class GoogleTool:
    def __init__(self):
        self.api_url = "https://google.serper.dev/search"
        self.headers = {
            "X-API-KEY": settings.SERPER_API_KEY,
            "Content-Type": "application/json",
        }

    async def search_spec(
        self, specific_query: str, item_name: str = ""
    ) -> tuple[str, str]:
        search_parts = [item_name.strip(), specific_query.strip(), "official specifications"]
        search_keyword = " ".join(part for part in search_parts if part)

        payload = {
            "q": search_keyword,
            "gl": "th",  # โฟกัสผลลัพธ์ในประเทศไทย
            "hl": "th",  # ดึงเนื้อหาภาษาไทยเป็นหลัก
            "num": 5,
        }

        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    self.api_url, headers=self.headers, json=payload, timeout=10.0
                )
                response.raise_for_status()
                results = response.json()

            sources = []
            for result in results.get("organic", [])[:5]:
                title = result.get("title", "").strip()
                link = result.get("link", "").strip()
                snippet = result.get("snippet", "").strip()
                if not any((title, link, snippet)):
                    continue

                sources.append(
                    f"ชื่อแหล่งข้อมูล: {title}\nURL: {link}\nข้อมูลสรุป: {snippet}"
                )

            if not sources:
                return "", "google_no_results"

            return "\n\n".join(sources), "checked_google"
        except Exception as e:
            print(f"[Google Search Error]: {str(e)}")
            return "", "google_search_failed"
