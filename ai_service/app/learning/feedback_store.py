import asyncio
import logging
import time
from difflib import SequenceMatcher
from typing import Any, Dict, List, Optional
import httpx

from config import settings

logger = logging.getLogger("uvicorn.error")


class FeedbackStore:
    """
    Manages feedback collection and continuous in-context learning for Yuemnoi AI.
    - Persists feedback (Thumbs Up/Down, reasons, comments) to Supabase table `ai_chat_feedback_tb`.
    - Caches recent feedback in-memory to power Real-time Dynamic In-Context Learning (Few-shot exemplars & guardrails).
    - Generates DPO/RLHF dataset format for future model fine-tuning.
    """

    CACHE_TTL_SECONDS = 300.0  # Refresh feedback cache every 5 minutes

    def __init__(self, client: httpx.AsyncClient):
        self.client = client
        self.headers = {
            "apikey": settings.SUPABASE_KEY,
            "Authorization": f"Bearer {settings.SUPABASE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }
        self.feedback_url = f"{settings.SUPABASE_URL.rstrip('/')}/rest/v1/ai_chat_feedback_tb"
        self._cached_feedback: List[Dict[str, Any]] = []
        self._cached_time: float = 0.0
        self._lock = asyncio.Lock()

    async def save_feedback(
        self,
        message_id: str,
        user_query: str,
        ai_response: str,
        rating: int,
        reason_category: Optional[str] = None,
        feedback_comment: Optional[str] = None,
        resolved_mode: Optional[str] = None,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Saves user thumbs up/down rating and comment to Supabase and updates cache immediately."""
        payload = {
            "message_id": message_id,
            "user_query": user_query.strip(),
            "ai_response": ai_response.strip(),
            "rating": rating,
            "reason_category": reason_category,
            "feedback_comment": feedback_comment.strip() if feedback_comment else None,
            "resolved_mode": resolved_mode,
            "user_id": user_id,
            "session_id": session_id,
        }

        # Clean None keys if needed or let PostgREST handle NULL
        record = {k: v for k, v in payload.items() if v is not None}

        try:
            resp = await self.client.post(
                self.feedback_url,
                headers=self.headers,
                json=record,
                timeout=10.0,
            )
            resp.raise_for_status()
            data = resp.json()
            saved = data[0] if isinstance(data, list) and data else record
            logger.info("Saved AI feedback for message_id=%s rating=%d", message_id, rating)
        except Exception as exc:
            logger.error("Failed to persist feedback to Supabase: %s", exc)
            saved = record

        # Optimistically update in-memory cache for immediate dynamic learning
        async with self._lock:
            self._cached_feedback.insert(0, saved)
            if len(self._cached_feedback) > 100:
                self._cached_feedback.pop()

        return saved

    async def get_recent_feedback(self, force_refresh: bool = False) -> List[Dict[str, Any]]:
        """Loads recent feedback from Supabase with caching."""
        now = time.monotonic()
        if not force_refresh and self._cached_feedback and (now - self._cached_time < self.CACHE_TTL_SECONDS):
            return list(self._cached_feedback)

        async with self._lock:
            if not force_refresh and self._cached_feedback and (time.monotonic() - self._cached_time < self.CACHE_TTL_SECONDS):
                return list(self._cached_feedback)

            params = {
                "select": "*",
                "order": "created_at.desc",
                "limit": "60",
            }
            try:
                resp = await self.client.get(
                    self.feedback_url,
                    headers={
                        "apikey": settings.SUPABASE_KEY,
                        "Authorization": f"Bearer {settings.SUPABASE_KEY}",
                    },
                    params=params,
                    timeout=10.0,
                )
                resp.raise_for_status()
                data = resp.json()
                if isinstance(data, list):
                    self._cached_feedback = data
                    self._cached_time = time.monotonic()
                    return list(self._cached_feedback)
            except Exception as exc:
                logger.warning("Could not refresh feedback cache from Supabase: %s", exc)
                return list(self._cached_feedback)

        return list(self._cached_feedback)

    async def get_learned_insights(self, query: str) -> Dict[str, List[str]]:
        """
        Dynamically extracts learned positive exemplars and negative constraints relevant to the current query.
        Used to augment system prompt (In-Context Learning like Gemini/ChatGPT).
        """
        all_feedback = await self.get_recent_feedback()
        if not all_feedback:
            return {"positive_exemplars": [], "negative_constraints": []}

        norm_q = query.lower().strip()
        positive_matches = []
        negative_matches = []

        for item in all_feedback:
            item_q = str(item.get("user_query") or "").lower().strip()
            if not item_q:
                continue

            # Calculate similarity or overlap
            sim = SequenceMatcher(None, norm_q, item_q).ratio()
            has_word_overlap = any(w in norm_q for w in item_q.split() if len(w) >= 3)

            if sim > 0.45 or has_word_overlap:
                rating = item.get("rating", 0)
                resp = str(item.get("ai_response") or "")[:200].replace("\n", " ").strip()
                comment = str(item.get("feedback_comment") or "").strip()
                reason = str(item.get("reason_category") or "").strip()

                if rating > 0:
                    positive_matches.append((sim, f"เมื่อผู้ใช้ถามแนว '{item_q}': แนวทางการตอบที่ผู้ใช้ถูกใจคือ: \"{resp}\""))
                elif rating < 0:
                    note = comment if comment else (f"เหตุผล: {reason}" if reason else "ผู้ใช้ระบุว่าตอบไม่ถูกต้องหรือไม่ตรงจุด")
                    negative_matches.append((sim, f"สำหรับคำถามแนว '{item_q}': ข้อควรระวัง -> {note} (ห้ามแนะนำอุปกรณ์หรือข้อมูลที่ผิดพลาดตามนี้)"))

        # Sort by similarity descending and pick top 2
        positive_matches.sort(key=lambda x: x[0], reverse=True)
        negative_matches.sort(key=lambda x: x[0], reverse=True)

        return {
            "positive_exemplars": [txt for _, txt in positive_matches[:2]],
            "negative_constraints": [txt for _, txt in negative_matches[:2]],
        }

    async def export_dpo_dataset(self) -> List[Dict[str, Any]]:
        """
        Generates DPO (Direct Preference Optimization) training pairs from user feedback.
        Format:
        [
          {
            "prompt": "...",
            "chosen": "...",
            "rejected": "..."
          }
        ]
        """
        all_feedback = await self.get_recent_feedback(force_refresh=True)
        # Group by normalized user_query
        by_query: Dict[str, Dict[str, Any]] = {}
        for item in all_feedback:
            q = str(item.get("user_query") or "").strip()
            if not q:
                continue
            norm = q.lower()
            if norm not in by_query:
                by_query[norm] = {"prompt": q, "chosen": [], "rejected": []}

            rating = item.get("rating", 0)
            resp = str(item.get("ai_response") or "").strip()
            if rating > 0 and resp:
                by_query[norm]["chosen"].append(resp)
            elif rating < 0 and resp:
                by_query[norm]["rejected"].append(resp)

        dpo_pairs = []
        for norm, data in by_query.items():
            if data["chosen"] and data["rejected"]:
                dpo_pairs.append({
                    "prompt": data["prompt"],
                    "chosen": data["chosen"][0],
                    "rejected": data["rejected"][0],
                })

        return dpo_pairs
