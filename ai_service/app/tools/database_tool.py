import asyncio
import re
import time
import httpx
import unicodedata
from difflib import SequenceMatcher
from typing import List, Dict, Any, Optional

from config import settings


class DatabaseTool:
    """Manages Supabase catalog retrieval, caching, and relevance-based ranking."""

    CACHE_TTL_SECONDS = 60.0

    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.headers = {
            "apikey": settings.SUPABASE_KEY,
            "Authorization": f"Bearer {settings.SUPABASE_KEY}",
        }
        self.items_url = f"{settings.SUPABASE_URL.rstrip('/')}/rest/v1/item_tb"
        self._cached_items: List[Dict[str, Any]] = []
        self._cached_time: float = 0.0
        self._refresh_lock = asyncio.Lock()

    async def list_available_items(self, force_refresh: bool = False) -> List[Dict[str, Any]]:
        """Fetch active/available items from Supabase with in-memory caching."""
        now = time.monotonic()
        if not force_refresh and self._cached_items and (now - self._cached_time < self.CACHE_TTL_SECONDS):
            return list(self._cached_items)

        async with self._refresh_lock:
            if not force_refresh and self._cached_items and (time.monotonic() - self._cached_time < self.CACHE_TTL_SECONDS):
                return list(self._cached_items)

            params = {
                "select": "id,item_name,item_image_url,description,category,price,status,type,created_at",
                "status": "eq.available",
                "limit": str(settings.MAX_CATALOG_ITEMS),
            }
            try:
                response = await self.client.get(
                    self.items_url,
                    headers=self.headers,
                    params=params,
                    timeout=10.0,
                )
                response.raise_for_status()
                data = response.json()
                if isinstance(data, list):
                    self._cached_items = data
                    self._cached_time = time.monotonic()
                    return list(self._cached_items)
            except Exception as e:
                # If network fails but we have cached items, return cached items
                if self._cached_items:
                    return list(self._cached_items)
                raise RuntimeError(f"Failed to fetch inventory from Supabase: {e}") from e

        return []

    async def get_items_by_ids(self, ids: List[int]) -> List[Dict[str, Any]]:
        """Retrieve specific items preserving the input ID order or matching cached items."""
        if not ids:
            return []

        all_items = await self.list_available_items()
        item_map = {item["id"]: item for item in all_items if "id" in item}

        result = []
        missing_ids = []
        for item_id in ids:
            if item_id in item_map:
                result.append(item_map[item_id])
            else:
                missing_ids.append(item_id)

        # If any item was not in available cache, fetch directly
        if missing_ids:
            try:
                params = {
                    "select": "id,item_name,item_image_url,description,category,price,status,type,created_at",
                    "id": f"in.({','.join(str(i) for i in missing_ids)})",
                }
                resp = await self.client.get(self.items_url, headers=self.headers, params=params, timeout=10.0)
                if resp.status_code == 200:
                    fetched = {row["id"]: row for row in resp.json() if isinstance(row, dict) and "id" in row}
                    for item_id in missing_ids:
                        if item_id in fetched:
                            result.append(fetched[item_id])
            except Exception:
                pass

        return result

    STOP_WORDS = {
        "อุปกรณ์", "สำหรับ", "การ", "ความ", "อื่น", "อื่นๆ", "อื่น ๆ", "ชุด",
        "นิ้ว", "ขนาด", "รุ่น", "ตัว", "ชิ้น", "คน", "วัน", "คืน", "เครื่อง", "และ", "หรือ",
        "แบบ", "ของ", "ที่", "มี", "ได้", "ให้", "ใน", "กับ", "เป็น", "จะ", "ไป", "มา"
    }

    ACTIVITY_THEMES = [
        {
            "category_indicators": ["แคม", "กลางแจ้ง", "เต็นท์", "camping"],
            "activity_keywords": ["เดินป่า", "เดินเขา", "ปีนเขา", "ขึ้นเขา", "ภูเขา", "ดอย", "แคมป์", "แคมปิ้ง", "กางเต็นท์", "เต็นท์", "trekking", "hike", "hiking", "กลางแจ้ง", "เข้าป่า"],
        },
        {
            "category_indicators": ["กล้อง", "ถ่ายภาพ", "photo", "camera"],
            "activity_keywords": ["ถ่ายรูป", "ถ่ายภาพ", "ถ่ายวิดีโอ", "ทำคลิป", "vlog", "พอร์ตเทรต", "กล้อง", "เลนส์", "โดรน", "โกโปร", "gopro"],
        },
        {
            "category_indicators": ["คอมพิวเตอร์", "ไอที", "computer", "it"],
            "activity_keywords": ["คอม", "คอมพิวเตอร์", "โน้ตบุ๊ก", "โน้ตบุค", "แล็ปท็อป", "macbook", "เขียนโค้ด", "ตัดต่อ", "ทำงาน"],
        },
        {
            "category_indicators": ["เครื่องเสียง", "จัดงาน", "ดนตรี", "audio"],
            "activity_keywords": ["ปาร์ตี้", "จัดงาน", "สัมมนา", "อีเวนต์", "งานแต่ง", "คอนเสิร์ต", "ร้องเพลง", "ดนตรี", "ลำโพง", "ไมค์", "ไมโครโฟน"],
        },
        {
            "category_indicators": ["กีฬา", "ออกกำลังกาย", "sport", "fitness"],
            "activity_keywords": ["ออกกำลังกาย", "วิ่ง", "ฟิตเนส", "ปั่นจักรยาน", "จักรยาน"],
        },
        {
            "category_indicators": ["เครื่องมือช่าง", "ก่อสร้าง", "tools"],
            "activity_keywords": ["งานช่าง", "ช่าง", "ซ่อมบ้าน", "สว่าน", "ฉีดน้ำ", "ซ่อม"],
        },
    ]

    UNSUPPORTED_DOMAINS = {
        "ยานพาหนะหรือรถเช่า": [
            "รถ", "รถตู้", "รถยนต์", "รถเก๋ง", "รถกระบะ", "รถมอเตอร์ไซค์", "มอเตอร์ไซค์",
            "มอไซค์", "จักรยานยนต์", "รถทัวร์", "รถบัส", "รถเช่า", "เช่ารถ",
            "alphard", "van", "car", "toyota", "honda", "isuzu", "benz", "bmw", "hyundai", "fortuner",
            "เรือ", "เรือยอชต์", "เรือเร็ว", "เครื่องบิน", "เฮลิคอปเตอร์"
        ],
        "ที่พักและอสังหาริมทรัพย์": [
            "บ้าน", "บ้านพัก", "คอนโด", "ห้องพัก", "โรงแรม", "รีสอร์ท", "ที่พัก", "หอพัก", "อพาร์ตเมนต์", "ที่ดิน"
        ],
        "สัตว์เลี้ยงหรือสิ่งมีชีวิต": [
            "สัตว์เลี้ยง", "หมา", "แมว", "สุนัข"
        ],
        "ตั๋วและบัตรโดยสาร": [
            "ตั๋วเครื่องบิน", "ตั๋วคอนเสิร์ต", "ตั๋วรถไฟ"
        ]
    }

    @classmethod
    def get_unsupported_category_name(cls, query: str) -> Optional[str]:
        """
        Detects if the query is seeking to rent an unsupported domain item (such as vehicles/cars,
        real estate, pets) rather than an equipment rental.
        If the query contains equipment modifiers (like 'กล้องติดรถ', 'เครื่องมือซ่อมรถ', 'ที่ชาร์จในรถ'),
        it is NOT treated as an unsupported domain.
        """
        norm = cls._normalize_thai(query)
        words = norm.split()

        equipment_hints = [
            "กล้อง", "ซ่อม", "เครื่องมือ", "สว่าน", "ฉีดน้ำ", "ล้าง", "แท่น", "ชาร์จ",
            "แบต", "ขาจับ", "ที่ยึด", "สาย", "ตัวแปลง", "เต็นท์", "ลำโพง", "ไมค์"
        ]
        if any(h in norm for h in equipment_hints):
            return None

        for domain_name, keywords in cls.UNSUPPORTED_DOMAINS.items():
            for kw in keywords:
                if kw in words:
                    return domain_name
                if len(kw) >= 3 and kw in norm:
                    return domain_name
        return None

    @staticmethod
    def _normalize_thai(text: str) -> str:
        text = unicodedata.normalize("NFKC", str(text or "")).lower()
        return re.sub(r"[^\w\s\u0e00-\u0e7f]", " ", text)

    @staticmethod
    def _strip_diacritics(s: str) -> str:
        s = unicodedata.normalize("NFKC", str(s or "")).replace("\u0e33", "\u0e4d\u0e32")
        # Only strip tone marks and specific diacritics, PRESERVING core phonetic vowels (ิ, ี, ึ, ื, ุ, ู, ั)
        return re.sub(r"[\u0e47-\u0e4e]", "", s)

    @staticmethod
    def extract_tokens(text: str) -> List[str]:
        """
        Dynamically extracts meaningful sub-tokens from Thai phrases by splitting
        compound conjunctions and delimiters (and, or, spaces, slashes, dashes).
        """
        if not text:
            return []
        raw = re.split(r"และ|หรือ|/|\s+|\(|\)|,|-", str(text))
        tokens = [str(text).strip()]
        for t in raw:
            t = t.strip()
            if len(t) >= 3 and t.lower() not in DatabaseTool.STOP_WORDS:
                tokens.append(t)
        return list(dict.fromkeys(tokens))

    @staticmethod
    def _fuzzy_contains(query: str, target: str, threshold: float = 0.68) -> tuple[bool, float]:
        """
        Universal dynamic fuzzy match checking if target (or a close typo) exists in query.
        """
        if not target or not query:
            return False, 0.0
        if target in query:
            return True, 1.0

        q_clean = DatabaseTool._strip_diacritics(query)
        t_clean = DatabaseTool._strip_diacritics(target)
        if len(t_clean) >= 3 and t_clean in q_clean:
            return True, 1.0

        tlen = len(t_clean)
        qlen = len(q_clean)
        # For short tokens (less than 4 Thai characters), do NOT use sliding window fuzzy matching!
        # In Thai phonetics, 2-letter substrings with vowels/tone marks will falsely match unrelated words.
        if tlen < 4 or qlen < 2:
            return False, 0.0

        best_r = 0.0
        min_span = max(3, tlen - 1)
        max_span = min(qlen, tlen + 1)
        for i in range(qlen):
            for span in range(min_span, max_span + 1):
                if i + span <= qlen:
                    sub = q_clean[i:i + span]
                    r = SequenceMatcher(None, sub, t_clean).ratio()
                    if r > best_r:
                        best_r = r

        adjusted_threshold = 0.75 if tlen >= 6 else 0.82
        return (best_r >= adjusted_threshold), best_r

    def rank_relevant_items(self, query: str, items: List[Dict[str, Any]], limit: int = 5) -> List[Dict[str, Any]]:
        """
        Rank items strictly based on relevance (keywords, semantic overlap, dynamic catalog tokens, and typo tolerance).
        Fully dynamic and catalog-driven.
        """
        if not items:
            return []

        # If user is asking for unsupported categories (cars, vans, houses, pets), do not return any equipment!
        if self.get_unsupported_category_name(query):
            return []

        norm_query = self._normalize_thai(query)
        q_clean = self._strip_diacritics(norm_query)
        query_words = [w for w in norm_query.split() if len(w) > 1 and w not in self.STOP_WORDS]

        scored: List[tuple[float, Dict[str, Any]]] = []

        for item in items:
            name = self._normalize_thai(item.get("item_name", ""))
            category = self._normalize_thai(item.get("category", ""))
            description = self._normalize_thai(item.get("description", ""))

            score = 0.0

            # 0. Activity / Theme Matching Boost (Maps user intentions like 'เดินป่า/ขึ้นเขา' to 'แคมปิ้งและกิจกรรมกลางแจ้ง')
            for theme in self.ACTIVITY_THEMES:
                if any(ind in category for ind in theme["category_indicators"]):
                    matched_kws = [kw for kw in theme["activity_keywords"] if kw in norm_query or kw in q_clean]
                    if matched_kws:
                        score += 15.0 * len(matched_kws)

            # 1. Direct full query match in title
            if norm_query in name and len(norm_query) >= 3:
                score += 20.0

            # 2. Individual query word matches
            for word in query_words:
                if word in name:
                    score += 6.0
                if word in category:
                    score += 4.0
                if word in description:
                    score += 1.5

            # 3. Dynamic token matching from item fields (name and category)
            all_tokens = self.extract_tokens(item.get("item_name", "")) + self.extract_tokens(item.get("category", ""))
            for token in all_tokens:
                token_clean = self._strip_diacritics(token)
                if len(token_clean) >= 3 and token_clean not in self.STOP_WORDS:
                    matched, ratio = self._fuzzy_contains(norm_query, token, threshold=0.68)
                    if matched:
                        weight = 8.0 if token in item.get("item_name", "") else 6.0
                        score += weight * ratio

            if score > 0:
                scored.append((score, item))

        # Sort by relevance score descending
        scored.sort(key=lambda x: x[0], reverse=True)

        if scored:
            return [item for _, item in scored[:limit]]

        # Only provide diverse fallback if user asked for general browsing or catalog overview
        general_browse_words = ("ทั้งหมด", "ทุกอย่าง", "อะไรบ้าง", "มีอะไร", "แนะนำ", "ของเช่า", "ยอดนิยม", "catalog")
        if any(w in norm_query for w in general_browse_words):
            categories_seen = set()
            diverse_items = []
            for item in items:
                cat = item.get("category", "")
                if cat not in categories_seen:
                    categories_seen.add(cat)
                    diverse_items.append(item)
                if len(diverse_items) >= limit:
                    break
            return diverse_items or items[:limit]

        return []
