from typing import Dict, Iterable, List, Optional, Set
from pydantic import BaseModel, Field, model_validator


class Item(BaseModel):
    """Domain entity representing a rental item from the catalog."""
    id: str
    name: str
    category: str
    # price/type คือเรตหลักที่ใช้แสดงผล ส่วน rates เก็บทุกหน่วยที่ประกาศให้เช่าจริง
    price: float = Field(ge=0, allow_inf_nan=False)
    type: str = "วัน"
    rates: Dict[str, float] = Field(default_factory=dict)
    status: str = "available"
    image_urls: List[str] = Field(default_factory=list)
    description: str = ""

    @model_validator(mode="after")
    def _primary_rate_is_listed(self):
        if not self.rates:
            self.rates = {self.type: self.price}
        return self

    @property
    def is_available(self) -> bool:
        return self.status.lower() == "available"

    @property
    def units(self) -> Set[str]:
        return {unit for unit in self.rates if unit.strip()}

    def rate(self, unit: str) -> Optional[float]:
        return self.rates.get(unit)

    def fits_budget(self, units: Iterable[str], maximum: float) -> bool:
        """ผ่านงบเมื่อมีเรตในหน่วยที่ผู้ใช้ระบุซึ่งไม่เกินเพดาน โดยไม่แปลงหน่วย"""
        return any(price <= maximum for unit in units if (price := self.rates.get(unit)) is not None)
