# tools/google_tool.py
import re
import html
from typing import List, Dict, Tuple, Any
import httpx
from config import settings
from ..telemetry import logger


class GoogleTool:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client
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
            "gl": "th",
            "hl": "th",
            "num": 5,
        }

        try:
            if settings.SERPER_API_KEY:
                response = await self.client.post(
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

                if sources:
                    return "\n\n".join(sources), "checked_google"

            # Fallback if no serper key or no results
            fb_sources, status = await self._fallback_search(search_keyword)
            if fb_sources:
                return "\n\n".join(fb_sources), status

            return "", "google_no_results"
        except Exception as e:
            logger.warning("Google search error=%s, trying fallback", type(e).__name__)
            fb_sources, status = await self._fallback_search(search_keyword)
            if fb_sources:
                return "\n\n".join(fb_sources), status
            return "", "google_search_failed"

    async def search_comparison(
        self, item_a: str, item_b: str, query: str = ""
    ) -> Tuple[str, List[Dict[str, str]], str]:
        """
        Searches internet for factual comparison, specs, and pros/cons between item_a and item_b.
        Performs snippet verification and returns (verified_summary_text, structured_sources, status).
        """
        # Formulate high-relevance search query
        clean_a = item_a.strip()
        clean_b = item_b.strip()

        if clean_a and clean_b:
            search_keyword = f"เปรียบเทียบ {clean_a} กับ {clean_b} ข้อดี ข้อเสีย สเปก ความแตกต่าง"
        elif clean_a:
            search_keyword = f"{clean_a} ข้อดี ข้อเสีย สเปก รีวิว"
        else:
            search_keyword = query.strip()

        payload = {
            "q": search_keyword,
            "gl": "th",
            "hl": "th",
            "num": 6,
        }

        raw_results = []
        status = "google_no_results"

        try:
            if settings.SERPER_API_KEY:
                response = await self.client.post(
                    self.api_url, headers=self.headers, json=payload, timeout=12.0
                )
                if response.status_code == 200:
                    data = response.json()
                    raw_results = data.get("organic", [])
                    status = "checked_google"
                else:
                    logger.warning("Serper status_code=%d, falling back", response.status_code)
        except Exception as e:
            logger.warning("Serper search comparison error=%s, trying fallback", type(e).__name__)

        # If primary search produced no results, try fallback search
        if not raw_results:
            fb_sources, fb_status = await self._fallback_search(search_keyword)
            if fb_sources:
                verified_text = "\n\n".join(fb_sources)
                return verified_text, [{"title": "Web Search", "url": "", "snippet": s} for s in fb_sources], fb_status

        # Verification & Snippet Filtering
        verified_sources, verified_text = self._verify_and_filter_snippets(raw_results, clean_a, clean_b)

        if not verified_sources:
            # Try English/broader query if specific Thai query yielded 0 verified
            if clean_a and clean_b:
                alt_keyword = f"{clean_a} vs {clean_b} differences pros cons specs"
                try:
                    alt_resp = await self.client.post(
                        self.api_url, headers=self.headers, json={"q": alt_keyword, "num": 5}, timeout=10.0
                    )
                    if alt_resp.status_code == 200:
                        raw_results = alt_resp.json().get("organic", [])
                        verified_sources, verified_text = self._verify_and_filter_snippets(raw_results, clean_a, clean_b)
                except Exception:
                    pass

        if not verified_text:
            return "", [], "no_verified_results"

        return verified_text, verified_sources, status

    def _verify_and_filter_snippets(
        self, raw_results: List[Dict[str, Any]], item_a: str, item_b: str
    ) -> Tuple[List[Dict[str, str]], str]:
        """
        Filters and verifies snippets to ensure factual accuracy:
        1. Strips HTML markup and decodes entities.
        2. Discards low-quality, empty, or ad-only snippets.
        3. Prioritizes snippets that contain relevant comparison terms or device mentions.
        """
        verified_sources = []
        formatted_blocks = []

        keywords_a = [w for w in item_a.lower().split() if len(w) > 2]
        keywords_b = [w for w in item_b.lower().split() if len(w) > 2]

        for res in raw_results:
            raw_title = str(res.get("title") or "").strip()
            raw_link = str(res.get("link") or "").strip()
            raw_snippet = str(res.get("snippet") or "").strip()

            clean_title = html.unescape(re.sub(r"<[^>]+>", "", raw_title))
            clean_snippet = html.unescape(re.sub(r"<[^>]+>", "", raw_snippet))

            if len(clean_snippet) < 25:
                continue

            # Check relevance: contains at least one of the items or general comparison keywords
            combined_lower = (clean_title + " " + clean_snippet).lower()
            has_relevance = (
                any(k in combined_lower for k in keywords_a)
                or any(k in combined_lower for k in keywords_b)
                or any(w in combined_lower for w in ("ต่าง", "เปรียบเทียบ", "ข้อดี", "ข้อเสีย", "สเปก", "vs", "review"))
            )

            if not has_relevance and (keywords_a or keywords_b):
                continue

            verified_sources.append({
                "title": clean_title,
                "url": raw_link,
                "snippet": clean_snippet,
            })

            formatted_blocks.append(
                f"- **แหล่งข้อมูล**: {clean_title}\n"
                f"  **ข้อเท็จจริง/สเปกที่พบ**: {clean_snippet}\n"
                f"  **ลิงก์อ้างอิง**: {raw_link}"
            )

        return verified_sources[:5], "\n\n".join(formatted_blocks[:5])

    async def _fallback_search(self, keyword: str) -> Tuple[List[str], str]:
        """DuckDuckGo HTML search fallback when primary search is unavailable."""
        try:
            resp = await self.client.post(
                "https://html.duckduckgo.com/html/",
                data={"q": keyword},
                headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
                timeout=8.0,
            )
            if resp.status_code == 200:
                html_text = resp.text
                snippets = re.findall(r'<a class="result__snippet[^>]*>(.*?)</a>', html_text, re.DOTALL)
                titles = re.findall(r'<a class="result__url[^>]*href="([^"]+)"[^>]*>(.*?)</a>', html_text, re.DOTALL)

                sources = []
                for i, snip in enumerate(snippets[:4]):
                    clean_snip = html.unescape(re.sub(r"<[^>]+>", "", snip)).strip()
                    if len(clean_snip) > 20:
                        sources.append(f"ข้อมูลสรุปจากอินเทอร์เน็ต: {clean_snip}")

                if sources:
                    return sources, "checked_fallback"
        except Exception as e:
            logger.warning("Fallback search error: %s", e)

        return [], "search_failed"

