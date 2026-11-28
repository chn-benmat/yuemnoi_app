from types import SimpleNamespace

import pytest
from pydantic_core import PydanticCustomError

from app.application.use_cases.query_items_use_case import QueryItemsUseCase
from app.domain.entities.catalog_guidance import PriceRequirement, SelectedItem, SelectionPlan
from app.domain.entities.item import Item


def _use_case():
    return QueryItemsUseCase(item_repository=None, llm_service=None, policy=SimpleNamespace(max_items=5))


def _plan(maximum):
    return SelectionPlan(
        mode="items", purpose="recommendation",
        selected_items=[SelectedItem(id="1", reason="ตรงงบรายวัน", evidence_fields=["rates"])],
        price_requirement=PriceRequirement(maximum=maximum, user_unit="daily", catalog_units=["daily"],
                                           interpretation="งบต่อวัน"),
        reasoning="เลือกจากเรตรายวัน")


def _decision(maximum):
    return SimpleNamespace(catalog_operation="selection", excluded_items=[], budget_max=maximum, budget_unit="daily")


# ประกาศมีเรตหลักรายชั่วโมง แต่ก็ให้เช่ารายวันด้วย
TRIPOD = Item(id="1", name="ขาตั้งกล้อง", category="กล้อง", price=80, type="hourly",
              rates={"hourly": 80, "daily": 300})


def test_a_daily_budget_accepts_an_item_whose_daily_rate_fits():
    _use_case().validate_selection(_plan(350), _decision(350), [TRIPOD])


def test_a_daily_budget_rejects_an_item_whose_daily_rate_is_over():
    with pytest.raises(PydanticCustomError):
        _use_case().validate_selection(_plan(250), _decision(250), [TRIPOD])


def test_the_catalog_shown_to_the_model_lists_every_rate():
    from app.application.services.catalog_guidance import catalog_snapshot, compact_catalog, presented_catalog

    presentation = {"amount_format": "f", "currency": "บาท", "price_template": "{amount} {currency}/{period}",
                    "unit_labels": {"hourly": "ชั่วโมง", "daily": "วัน"}, "status_labels": {}}
    catalog = compact_catalog(presented_catalog(catalog_snapshot([TRIPOD]), [TRIPOD], presentation))
    row = dict(zip(catalog["columns"], catalog["rows"][0]))

    assert row["rates"] == {"hourly": 80, "daily": 300}
    assert row["rates_display"] == ["80 บาท/ชั่วโมง", "300 บาท/วัน"]
