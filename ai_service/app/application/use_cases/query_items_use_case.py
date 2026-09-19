import logging
from typing import List, Optional
from app.domain.entities.intent_decision import IntentDecision
from app.domain.entities.item import Item
from app.domain.entities.semantic_item_filter import SemanticItemFilterDecision
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.infrastructure.prompts.prompt_templates import SEMANTIC_ITEM_FILTER_PROMPT

logger = logging.getLogger(__name__)


class QueryItemsUseCase:
    """Retrieves and ranks candidate items from repository matching user constraints with zero bias and zero hardcoded keywords."""

    def __init__(
        self,
        item_repository: ItemRepositoryInterface,
        llm_service: Optional[LLMServiceInterface] = None,
    ):
        self._item_repo = item_repository
        self._llm = llm_service

    async def execute(
        self,
        decision: IntentDecision,
        limit: int = 5,
    ) -> List[Item]:
        all_items = await self._item_repo.get_all_items()
        if not all_items:
            return []

        has_specific_search = bool(
            decision.target_items or decision.categories or decision.intended_use or decision.budget_max
        )

        # 1. AI-Native Semantic Selection via LLM Structured Output
        if self._llm and has_specific_search:
            try:
                catalog_lines = []
                for it in all_items:
                    desc = f", รายละเอียด: {it.description}" if it.description else ""
                    avail = "พร้อมให้เช่า" if it.is_available else "ไม่ว่าง"
                    catalog_lines.append(
                        f"- ID: {it.id} | ชื่อ: {it.name} | หมวดหมู่: {it.category} | ค่าเช่า: {it.price} บาท | สถานะ: {avail}{desc}"
                    )
                catalog_str = "\n".join(catalog_lines)

                constraints = []
                if decision.target_items:
                    constraints.append(f"อุปกรณ์เป้าหมายที่ระบุ: {', '.join(decision.target_items)}")
                if decision.categories:
                    constraints.append(f"หมวดหมู่อุปกรณ์: {', '.join(decision.categories)}")
                if decision.intended_use:
                    constraints.append(f"วัตถุประสงค์การใช้งาน: {decision.intended_use}")
                if decision.budget_max is not None and decision.budget_max > 0:
                    constraints.append(f"งบประมาณสูงสุด: {decision.budget_max} บาท")

                prompt = (
                    f"รายการอุปกรณ์ทั้งหมดในคลังระบบยืมหน่อย:\n{catalog_str}\n\n"
                    f"ข้อกำหนดและความต้องการของผู้ใช้:\n" + "\n".join(constraints) + "\n\n"
                    f"กำหนดขีดจำกัดเพดานสูงสุด limit = {limit}\n"
                    "คำสั่ง: กรุณาวิเคราะห์เชิงความหมาย (Semantic Reasoning) และเลือกเฉพาะ ID ของอุปกรณ์ที่ตรงกับความต้องการและชนิดอุปกรณ์ของผู้ใช้อย่างแท้จริง "
                    "หากมีสินค้าที่ตรงเพียง 1 หรือ 2 ชิ้น ให้คืนค่าเฉพาะ ID นั้นเท่านั้น ห้ามเลือกสินค้าที่ไม่เกี่ยวข้องมาเติมให้เต็ม limit เด็ดขาด "
                    "หากไม่มีสินค้าที่ตรงเลย ให้คืนค่า matched_item_ids เป็นรายการว่าง []"
                )

                filter_decision = await self._llm.generate_structured(
                    prompt=prompt,
                    schema=SemanticItemFilterDecision,
                    system_instruction=SEMANTIC_ITEM_FILTER_PROMPT,
                    temperature=0.1,
                )

                if filter_decision and filter_decision.matched_item_ids:
                    id_map = {i.id: i for i in all_items}
                    matched_items = [id_map[i_id] for i_id in filter_decision.matched_item_ids if i_id in id_map]
                    # Strictly treat limit as an upper ceiling, never backfill
                    return matched_items[:limit]
                return []
            except Exception as e:
                logger.warning(f"Semantic item retrieval via LLM failed, using deterministic fallback: {e}")

        # 2. Pure String-Based Deterministic Fallback (Zero-Hardcode & Zero-Keyword)
        target_tokens = [t.lower().strip() for t in decision.target_items if t.strip()]
        category_tokens = [c.lower().strip() for c in decision.categories if c.strip() and c.strip() != "อื่น ๆ"]
        use_lower = (decision.intended_use or "").lower().strip()
        use_words = [w for w in use_lower.split() if len(w) >= 2] if use_lower else []

        # If target equipment is specified, strictly isolate to items matching target name/description
        if target_tokens:
            target_matching_items = []
            for item in all_items:
                name_l = item.name.lower()
                desc_l = (item.description or "").lower()
                if any(t in name_l or t in desc_l for t in target_tokens):
                    target_matching_items.append(item)
                elif any(all(w in name_l for w in t.split()) for t in target_tokens if " " in t):
                    target_matching_items.append(item)

            if target_matching_items:
                candidates_pool = target_matching_items
            else:
                # Target was requested, but no item in catalog matched the target name/desc
                cat_match = [item for item in all_items if any(t in item.category.lower() for t in target_tokens)]
                if cat_match:
                    candidates_pool = cat_match
                else:
                    return []
        elif category_tokens:
            candidates_pool = [
                item for item in all_items
                if any(c in item.category.lower() or item.category.lower() in c for c in category_tokens)
            ]
            if not candidates_pool and decision.categories != ["อื่น ๆ"]:
                return []
        else:
            candidates_pool = all_items

        # Check if the requested category has any item matching intended_use
        category_has_intended_use_match = False
        if decision.intended_use and category_tokens:
            for item in all_items:
                cat_match = any(c in item.category.lower() or item.category.lower() in c for c in category_tokens)
                if cat_match:
                    desc_l = (item.description or "").lower()
                    name_l = item.name.lower()
                    if use_lower in desc_l or use_lower in name_l:
                        category_has_intended_use_match = True
                        break
                    if any(w in desc_l or w in name_l for w in use_words):
                        category_has_intended_use_match = True
                        break

        allow_cross_category_intended_use = (
            bool(decision.intended_use)
            and bool(category_tokens)
            and not category_has_intended_use_match
            and not bool(target_tokens)
        )

        scored_items = []
        for item in candidates_pool:
            score = 0.0
            name_l = item.name.lower()
            desc_l = (item.description or "").lower()
            cat_l = item.category.lower()

            if target_tokens:
                for t in target_tokens:
                    if t in name_l:
                        score += 10.0
                    elif t in desc_l:
                        score += 5.0

            if category_tokens:
                for c in category_tokens:
                    if c in cat_l or cat_l in c:
                        score += 5.0
                    elif c in name_l:
                        score += 3.0

            if use_lower:
                if use_lower in desc_l or use_lower in name_l:
                    score += 12.0
                elif use_lower in cat_l:
                    score += 8.0
                else:
                    matched_words = [w for w in use_words if w in desc_l or w in name_l or w in cat_l]
                    if matched_words:
                        score += 4.0 * len(matched_words)

            if item.is_available:
                score += 1.0

            if decision.budget_max is not None and decision.budget_max > 0:
                if item.price <= decision.budget_max:
                    score += 2.0
                else:
                    score -= 5.0

            scored_items.append((score, item))

        if allow_cross_category_intended_use:
            for item in all_items:
                if item in candidates_pool:
                    continue
                name_l = item.name.lower()
                desc_l = (item.description or "").lower()
                cat_l = item.category.lower()

                use_match = (use_lower in desc_l or use_lower in name_l or use_lower in cat_l)
                if not use_match and use_words:
                    use_match = any(w in desc_l or w in name_l or w in cat_l for w in use_words)

                if use_match:
                    score = 10.0
                    if use_lower in desc_l or use_lower in name_l:
                        score += 5.0
                    if item.is_available:
                        score += 1.0
                    scored_items.append((score, item))

        scored_items.sort(key=lambda x: x[0], reverse=True)

        candidates = [item for score, item in scored_items if score > 1.0]

        if decision.budget_max is not None and decision.budget_max > 0:
            candidates = [c for c in candidates if c.price <= decision.budget_max]

        if not candidates and not has_specific_search and scored_items:
            candidates = [item for score, item in scored_items if item.is_available]

        # Strictly return up to limit, never backfill
        return candidates[:limit]
