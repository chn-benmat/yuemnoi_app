from typing import List, Optional
from pydantic import BaseModel, Field
from app.domain.entities.item import Item
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.domain.interfaces.cache_service import CacheServiceInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.core.logging import logger

class SingleItemMatch(BaseModel):
    analysis: str = Field(..., description="วิเคราะห์ว่าสิ่งที่ค้นหาคืออะไร และตรวจสอบอย่างรอบคอบว่ามีสินค้าชนิดนี้/รุ่นนี้อยู่ใน Catalog หรือไม่")
    is_specific_model_or_brand: bool = Field(
        default=True,
        description="True หากสิ่งที่ค้นหาเป็น 'ชื่อแบรนด์หรือชื่อรุ่นสินค้าเฉพาะเจาะจง' หรือสิ่งของเฉพาะชิ้น (เช่น 'Sony', 'Canon R50', 'iPhone 15 Pro', 'Fujifilm', 'เสื้อ', 'ตู้เย็น') แต่เป็น False หากเป็นข้อความบรรยายคุณลักษณะ สเปกการใช้งาน หรือตัวเลือกแบบสอบถาม (เช่น 'สมาร์ตโฟนจอใหญ่สำหรับทำงาน', 'กล้องท่องเที่ยว/Vlog', 'คอมทำงานกราฟิก', 'มือถือจอใหญ่')"
    )
    is_in_catalog: bool = Field(..., description="ระบุ True เฉพาะเมื่อมีสินค้าชนิดนี้หรือรุ่นนี้อยู่ใน Catalog จริงๆ และระบุ False หากไม่มีสินค้าชนิดนี้ใน Catalog เลย")
    item_id: int = Field(0, description="ID ตัวเลขของสินค้าใน Catalog ที่ตรงกัน (หาก is_in_catalog=False หรือไม่มีในร้าน ต้องตอบ 0 เท่านั้น ห้ามเลือกสินค้าอื่นมาแทน)")
    matched_name: str = Field("", description="ชื่อของสินค้าใน Catalog ที่ตรงกัน (คัดลอกจาก Catalog เท่านั้น หากไม่มีให้ตอบ '')")
    confidence: float = Field(0.0, description="ระดับความมั่นใจ 0.0 ถึง 1.0 (หากไม่มีสินค้าให้ตอบ 0.0)")

class RankedItemSelection(BaseModel):
    selected_ids: List[int] = Field(default_factory=list, description="รายการ ID ของสินค้าที่ตรงกับคำขอของผู้ใช้มากที่สุด")
    relevance_explanation: str = Field("", description="คำอธิบายเหตุผลสั้นๆ")

class ItemModelName(BaseModel):
    id: int = Field(..., description="ID ของสินค้าใน Catalog")
    model_name: str = Field(
        ..., 
        description="ชื่อแบรนด์และชื่อรุ่นสั้นกระชับเท่านั้น เช่น 'Canon EOS R50', 'PlayStation 5', 'Yamaha F310', 'Yamaha PSR-E373', 'MacBook Air M2 13 นิ้ว', 'Nintendo Switch OLED' (ตัดคำนำหน้าภาษาไทยเช่น 'กีตาร์โปร่ง', 'คีย์บอร์ดไฟฟ้า', 'กล้อง', 'จอมอนิเตอร์' ออก และตัดของแถมออกทั้งหมด)"
    )

class CatalogModelNames(BaseModel):
    items: List[ItemModelName]

class QueryItemsUseCase:
    """Retrieves and semantically ranks rental items from item_tb without hardcode/regex."""

    CACHE_KEY = "all_items_catalog"

    def __init__(
        self,
        item_repo: ItemRepositoryInterface,
        cache_service: CacheServiceInterface,
        llm_service: LLMServiceInterface,
        cache_ttl_seconds: int = 600
    ):
        self.item_repo = item_repo
        self.cache_service = cache_service
        self.llm_service = llm_service
        self.cache_ttl = cache_ttl_seconds

    async def refresh_catalog_cache(self, ttl_seconds: Optional[int] = None) -> List[Item]:
        """บังคับดึงข้อมูลจาก Supabase และสกัดชื่อรุ่นสากลใหม่ลง Cache ทันที (Background Warm-up & Stale-While-Revalidate)"""
        try:
            raw_items = await self.item_repo.get_all_items()
            if not raw_items:
                return []

            def _snap_full_tokens(model_name: str, raw_name: str) -> str:
                """Zero-regex, zero-keyword helper to snap any accidentally truncated model suffix to the full word in raw_name."""
                if not model_name or not raw_name:
                    return model_name
                raw_words = raw_name.split()
                model_words = model_name.split()
                if not model_words:
                    return model_name
                last_word = model_words[-1]
                for rw in raw_words:
                    if len(rw) > len(last_word) and rw.lower().startswith(last_word.lower()):
                        return " ".join(model_words[:-1] + [rw])
                return model_name

            # Check if model names are already cached
            cached_models = await self.cache_service.get(f"{self.CACHE_KEY}:models")
            if cached_models and isinstance(cached_models, dict):
                enriched = []
                for it in raw_items:
                    m_name = cached_models.get(str(it.id)) or cached_models.get(it.id) or it.item_name
                    m_name = _snap_full_tokens(m_name, it.item_name)
                    enriched.append(Item(
                        id=it.id,
                        user_id=it.user_id,
                        item_name=it.item_name,
                        item_image_url=it.item_image_url,
                        description=it.description,
                        category=it.category,
                        price=it.price,
                        status=it.status,
                        type=it.type,
                        created_at=it.created_at,
                        updated_at=it.updated_at,
                        model_name=m_name
                    ))
                effective_ttl = ttl_seconds if ttl_seconds is not None else self.cache_ttl
                await self.cache_service.set(self.CACHE_KEY, enriched, ttl_seconds=effective_ttl)
                return enriched

            # Use LLM to extract clean model names once during cache refresh
            catalog_lines = [f"ID: {it.id} | ชื่อเดิม: {it.item_name}" for it in raw_items]
            catalog_summary = "\n".join(catalog_lines)
            prompt = (
                f"ให้สกัด 'ชื่อแบรนด์และชื่อรุ่นสากล' ของสินค้าแต่ละชิ้นจากรายการด้านล่าง:\n\n{catalog_summary}\n\n"
                f"กฎเหล็กในการสกัดชื่อรุ่น:\n"
                f"1. สกัดเฉพาะ 'แบรนด์ + ชื่อรุ่นสากล + มิติหลัก (ถ้ามี)' เช่น:\n"
                f"   - 'กล้อง Canon EOS R50 พร้อมเลนส์' -> 'Canon EOS R50'\n"
                f"   - 'เครื่องเล่นเกม PlayStation 5 (PS5) รุ่นใส่แผ่น' -> 'PlayStation 5'\n"
                f"   - 'กีตาร์โปร่ง Yamaha F310 พร้อมกระเป๋า' -> 'Yamaha F310'\n"
                f"   - 'คีย์บอร์ดไฟฟ้า Yamaha PSR-E373 พร้อมขาตั้ง' -> 'Yamaha PSR-E373'\n"
                f"   - 'Apple MacBook Air M2 13 นิ้ว สีสเปซเกรย์' -> 'MacBook Air M2 13 นิ้ว'\n"
                f"   - 'เครื่องเล่นเกม Nintendo Switch OLED สีขาว' -> 'Nintendo Switch OLED'\n"
                f"   - 'จอมอนิเตอร์ Dell UltraSharp 27 นิ้ว 4K' -> 'Dell UltraSharp 27 นิ้ว 4K'\n"
                f"   - 'สว่านกระแทกไร้สาย Bosch GSB 185-LI' -> 'Bosch GSB 185-LI'\n"
                f"   - 'เต็นท์แคมป์ปิ้ง Coleman Instant Cabin 4 คน' -> 'Coleman Instant Cabin 4 คน'\n"
                f"   - 'โปรเจกเตอร์ Wanbo T2 Max Full HD' -> 'Wanbo T2 Max'\n"
                f"2. ห้ามตัดทอนตัวเลขท้ายชื่อรุ่นเด็ดขาด เช่น 'Yamaha F310' ห้ามตัดเป็น 'Yamaha F31', 'Yamaha PSR-E373' ห้ามตัดเป็น 'Yamaha PSR-E37'\n"
                f"3. ตัดคำนำหน้าประเภทสินค้าภาษาไทยออกทั้งหมด (เช่น กีตาร์โปร่ง, คีย์บอร์ดไฟฟ้า, เครื่องเล่นเกม, กล้องมิลเลอร์เลส, กล้อง, สว่านกระแทก, เต็นท์, จอมอนิเตอร์)\n"
                f"4. ตัดของแถมและอุปกรณ์เสริมทั้งหมดออก (เช่น พร้อมเลนส์, พร้อมกระเป๋า, พร้อมขาตั้ง, พร้อมจอย 2 ตัว)\n"
                f"5. ส่งคืนเป็น JSON รายการสินค้าครบทุก ID ตาม Schema CatalogModelNames"
            )

            res = await self.llm_service.generate_structured(
                prompt=prompt,
                response_model=CatalogModelNames,
                system_instruction="คุณเป็นผู้เชี่ยวชาญการสกัดชื่อรุ่นสินค้าสากล ตอบเป็น JSON เท่านั้น",
                temperature=0.0
            )

            id_to_model = {item.id: item.model_name for item in res.items}
            enriched = []
            for it in raw_items:
                m_name = id_to_model.get(it.id, it.item_name)
                m_name = _snap_full_tokens(m_name, it.item_name)
                enriched.append(Item(
                    id=it.id,
                    user_id=it.user_id,
                    item_name=it.item_name,
                    item_image_url=it.item_image_url,
                    description=it.description,
                    category=it.category,
                    price=it.price,
                    status=it.status,
                    type=it.type,
                    created_at=it.created_at,
                    updated_at=it.updated_at,
                    model_name=m_name
                ))

            # Store in cache
            effective_ttl = ttl_seconds if ttl_seconds is not None else self.cache_ttl
            await self.cache_service.set(self.CACHE_KEY, enriched, ttl_seconds=effective_ttl)
            await self.cache_service.set(f"{self.CACHE_KEY}:models", id_to_model, ttl_seconds=effective_ttl)
            return enriched
        except Exception as e:
            logger.error(f"Error during catalog cache refresh: {e}")
            # Stale-While-Revalidate: คืนค่าจากแคชเดิมถ้ามีอยู่ เพื่อไม่ให้ระบบล่ม
            cached = await self.cache_service.get(self.CACHE_KEY)
            if cached is not None:
                logger.info("Serving stale cached catalog items due to refresh error.")
                return cached
            raise

    async def get_all_cached_items(self, force_refresh: bool = False) -> List[Item]:
        if not force_refresh:
            cached = await self.cache_service.get(self.CACHE_KEY)
            if cached is not None and isinstance(cached, list):
                return cached
        return await self.refresh_catalog_cache()

    async def execute(
        self,
        user_query: str,
        target_item_names: Optional[List[str]] = None,
        category_hints: Optional[List[str]] = None,
        intended_use: Optional[str] = None,
        budget_max: Optional[float] = None,
        limit: int = 3
    ) -> List[Item]:
        all_items = await self.get_all_cached_items()
        if not all_items:
            return []

        item_map = {it.id: it for it in all_items}
        available_items = [it for it in all_items if it.is_available]

        # 1. If specific target items are extracted, match each target directly using semantic classification
        # ค้นหาจากรายการสินค้าทั้งหมดในร้าน (รวมสินค้าที่ถูกเช่าอยู่) โดยจำกัดขอบเขตตามหมวดหมู่ถ้ามี
        if target_item_names and len(target_item_names) > 0:
            matched_items: List[Item] = []
            has_non_specific_target = False
            target_pool = [it for it in all_items if it.category in category_hints] if category_hints else all_items
            if not target_pool:
                target_pool = all_items
            catalog_lines = [
                f"ID: {it.id} | {it.display_name} (หมวด: {it.category}) | สถานะ: {'พร้อมเช่า' if it.is_available else 'ไม่พร้อมเช่า'}"
                for it in target_pool
            ]
            catalog_text = "\n".join(catalog_lines)

            for target in target_item_names[:limit]:
                prompt = (
                    f"ตรวจสอบว่ามีสินค้า \"{target}\" อยู่ใน Catalog ของร้านหรือไม่:\n\n"
                    f"Catalog สินค้าในร้าน:\n{catalog_text}\n\n"
                    f"หลักเกณฑ์การจับคู่สินค้าใน Catalog:\n"
                    f"1. รองรับชื่อรุ่นที่เป็นทางการและชื่อเรียกย่อทั่วไป (Shorthand / Aliases): เช่น 'Sony A7 IV' ตรงกับ 'Sony Alpha A7 IV', 'Canon R50' ตรงกับ 'Canon EOS R50', 'PS5' ตรงกับ 'PlayStation 5', 'MacBook Air M2' ตรงกับ 'MacBook Air M2 13 นิ้ว'\n"
                    f"2. รองรับการค้นหาด้วยชื่อแบรนด์ (Brand Matching): หากระบุเพียงชื่อแบรนด์กว้างๆ (เช่น 'Sony', 'Canon', 'Apple', 'Yamaha') โดยไม่ระบุเลขรุ่น ให้จับคู่กับสินค้าของแบรนด์นั้นใน Catalog ได้\n"
                    f"3. ห้ามจับคู่ข้ามแบรนด์ ข้ามรุ่น หรือข้ามชนิดอุปกรณ์เด็ดขาด (Strict No-Cross-Matching):\n"
                    f"   - ห้ามจับคู่คนละแบรนด์โดยเด็ดขาด (เช่น ค้นหา 'Fujifilm' หรือ 'Nikon' แต่ใน Catalog มีแค่ Canon หรือ Sony ถือว่าไม่มีในร้าน ให้ตอบ is_in_catalog = False, item_id = 0)\n"
                    f"   - ห้ามจับคู่ข้ามรุ่นคนละโมเดล (เช่น ค้นหา 'iPhone 17' หรือ 'vivo v30' แต่ในร้านมีแค่ 'iPhone 15 Pro' ถือว่าไม่มีในร้าน ให้ตอบ is_in_catalog = False, item_id = 0)\n"
                    f"   - ห้ามจับคู่สินค้าคนละประเภทโดยสิ้นเชิง (เช่น ค้นหา 'เสื้อ', 'รถยนต์' แต่ร้านมีแต่กล้อง/คอม/เครื่องใช้ ให้ตอบ is_in_catalog = False, item_id = 0)\n"
                    f"4. ตอบเป็น JSON ตาม Schema SingleItemMatch โดยวิเคราะห์ในช่อง analysis และประเมิน is_specific_model_or_brand ก่อนตัดสินใจ"
                )
                try:
                    match_res = await self.llm_service.generate_structured(
                        prompt=prompt,
                        response_model=SingleItemMatch,
                        system_instruction="คุณเป็น AI ช่วยตรวจสอบและค้นหาสินค้าใน Catalog ตอบเป็น JSON ตามความเป็นจริงอย่างเป็นกลาง",
                        temperature=0.0
                    )
                    logger.info(f"Target match for '{target}': in_catalog={match_res.is_in_catalog}, item_id={match_res.item_id}, matched_name='{match_res.matched_name}', conf={match_res.confidence}, is_specific={match_res.is_specific_model_or_brand}")
                    if not match_res.is_specific_model_or_brand:
                        has_non_specific_target = True
                    if (
                        match_res.is_in_catalog
                        and match_res.item_id > 0
                        and match_res.item_id in item_map
                    ):
                        item = item_map[match_res.item_id]
                        if category_hints and item.category not in category_hints:
                            logger.warning(f"Item {item.display_name} (cat: {item.category}) does not match category_hints {category_hints}. Skipping.")
                            continue
                        if item not in matched_items:
                            matched_items.append(item)
                except Exception as e:
                    logger.warning(f"Error matching target '{target}': {e}")

            if matched_items:
                return matched_items[:limit]

            # หากไม่พบสินค้าที่ตรงกัน:
            # หากคำค้นหาไม่ใช่ชื่อรุ่น/แบรนด์เฉพาะเจาะจง (เช่น เป็นคำบรรยาย หรือช้อยส์แบบสอบถาม 'สมาร์ตโฟนจอใหญ่สำหรับทำงาน')
            # หรือมี category_hints ที่ระบุหมวดหมู่ของร้าน ให้ fallback ไปทำการคัดเลือกและจัดอันดับสินค้าตามหมวดหมู่ (Category Ranking)
            # เพื่อแนะนำอุปกรณ์ที่เหมาะสมในร้าน เช่น Samsung Galaxy S24 Ultra / iPhone 15 Pro แทนที่จะตอบว่าไม่มีสินค้า
            if has_non_specific_target or category_hints:
                logger.info(f"Target items {target_item_names} are descriptive or category-scoped, falling back to category ranking pool.")
                extra_use = ", ".join(target_item_names)
                intended_use = f"{extra_use}, {intended_use}" if intended_use else extra_use
            else:
                # ผู้ใช้ระบุชื่อแบรนด์/รุ่นเฉพาะเจาะจง หรือสิ่งของนอกร้านจริง (เช่น 'Fujifilm', 'เสื้อ') และร้านไม่มี
                # ให้ส่งคืน [] ตามนโยบาย No-Alternative Policy
                return []

        # 2. General query or category search: rank only available items scoped by category
        catalog_pool = available_items if available_items else all_items
        if category_hints:
            scoped_pool = [it for it in catalog_pool if it.category in category_hints]
            if scoped_pool:
                catalog_pool = scoped_pool
            else:
                # ร้านไม่มีสินค้าในหมวดหมู่ที่ผู้ใช้ระบุเลย
                return []

        catalog_lines = [
            f"ID: {it.id} | สินค้า: {it.display_name} | หมวด: {it.category} | ราคา: {it.price} บ./{it.type}"
            for it in catalog_pool
        ]
        catalog_text = "\n".join(catalog_lines)
        category_str = f" | หมวดหมู่: {category_hints}" if category_hints else ""
        use_str = f" | วัตถุประสงค์การใช้งาน: {intended_use}" if intended_use else ""
        budget_str = f" | งบประมาณสูงสุด: {budget_max} บาท" if budget_max else ""

        prompt = (
            f"คำขอของผู้ใช้: \"{user_query}\"{category_str}{use_str}{budget_str}\n\n"
            f"รายการสินค้าพร้อมให้เช่าในร้านค้า (Catalog):\n"
            f"{catalog_text}\n\n"
            f"หลักเกณฑ์การคัดเลือกสินค้าอย่างเคร่งครัด:\n"
            f"1. คัดเลือกเฉพาะ ID ของสินค้าที่เป็นประเภทอุปกรณ์ที่ผู้ใช้ต้องการโดยตรงเท่านั้น (สูงสุด {limit} รายการ เช่น หากผู้ใช้ระบุต้องการกล้อง ให้เลือกเฉพาะอุปกรณ์ที่เป็นตัวกล้องถ่ายภาพเท่านั้น ห้ามเลือกอุปกรณ์เสริม เช่น ชุดไฟสตูดิโอ หรือของหมวดอื่นมาปนเด็ดขาด)\n"
            f"2. ห้ามนำสินค้าที่ไม่เกี่ยวข้องหรือไม่ตรงประเภทมาเติมเพื่อให้ครบ {limit} รายการโดยเด็ดขาด\n"
            f"3. เกณฑ์การจัดลำดับอย่างเป็นกลาง (Fairness & Diversity Ranking): หากมีการระบุงบประมาณ ให้คัดเลือกสินค้าที่สอดคล้องกับงบประมาณเป็นอันดับแรก แต่หากไม่ได้ระบุงบประมาณ ให้คัดเลือกสินค้าที่ตอบโจทย์การใช้งานและกระจายความหลากหลายของระดับราคา/สเปกเพื่อเป็นทางเลือกแก่ผู้ใช้ แทนการเลือกเฉพาะสินค้าลำดับแรกๆ ใน Catalog\n"
            f"4. หากคำขอของผู้ใช้เป็นการขอตัวเลือกที่ราคาถูกกว่าหรือประหยัดกว่า (Cheaper Alternative): ให้คัดเลือกเฉพาะสินค้าที่มีราคาเช่าถูกกว่าราคาเดิมที่ระบุในงบประมาณอย่างแท้จริง และหากในร้านไม่มีสินค้าอื่นในหมวดนั้นที่ราคาถูกกว่า ให้ระบุ selected_ids เป็นรายการว่าง []\n"
            f"5. หากมีสินค้าที่ตรงตามความต้องการเพียง 1 รายการ ให้ส่งกลับเฉพาะ ID รายการนั้นเพียง 1 รายการเท่านั้น ห้ามเติมสินค้าอื่น และหากไม่มีสินค้าที่ตรงเลย ให้ระบุ selected_ids เป็นรายการว่าง []"
        )

        try:
            ranking = await self.llm_service.generate_structured(
                prompt=prompt,
                response_model=RankedItemSelection,
                system_instruction="คุณเป็น AI คัดเลือกสินค้าในร้านเช่า ตอบเป็น JSON",
                temperature=0.0
            )
            matched = [item_map[i_id] for i_id in ranking.selected_ids if i_id in item_map and item_map[i_id].is_available]
            if matched:
                return matched[:limit]
            return []
        except Exception as e:
            logger.error(f"Error ranking items with LLM: {e}")
            return []

    async def get_available_categories(self) -> List[str]:
        """Dynamically retrieve available unique categories from cached inventory."""
        items = await self.get_all_cached_items()
        return sorted(list(set(it.category for it in items if it.category and it.category != "อื่น ๆ")))


