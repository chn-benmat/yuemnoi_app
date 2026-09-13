import pytest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.config import get_settings
from app.infrastructure.llm.ollama_client import OllamaClient
from app.application.services.fact_verification import FactVerificationService

@pytest.mark.asyncio
async def test_fact_verification_filtering():
    settings = get_settings()
    llm = OllamaClient(settings)
    verifier = FactVerificationService(llm)

    raw_search = [
        {
            "title": "เปรียบเทียบ Sony A7 IV vs Canon EOS R50 สเปกกล้อง",
            "link": "https://camera-expert.example.com/a7iv-vs-r50",
            "snippet": "Sony A7 IV ใช้เซนเซอร์ Full-frame BSI 33 ล้านพิกเซล ส่วน Canon EOS R50 ใช้เซนเซอร์ APS-C 24.2 ล้านพิกเซล น้ำหนักเบากว่ามาก เหมาะสำหรับพกพา"
        },
        {
            "title": "ซื้อของลดราคา ช้อปปิ้งออนไลน์ แจกโค้ดฟรี โทรศัพท์ราคาถูก",
            "link": "https://spam-shopping.example.com/promo",
            "snippet": "ลดราคาสินค้าแฟชั่น เสื้อผ้า กางเกง ส่งฟรีทั่วไทย ช้อปเลยวันนี้ รับคูปอง 50% ทันที"
        }
    ]

    result = await verifier.verify_and_filter(
        item_a_name="Sony Alpha A7 IV",
        item_b_name="Canon EOS R50",
        raw_search_results=raw_search
    )

    assert len(result.verified_specs) > 0
    for src in result.filtered_sources:
        assert "เสื้อผ้า" not in src.snippet
