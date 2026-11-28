from app.domain.entities.item import Item


def _tripod(**rates):
    return Item(id="1", name="ขาตั้งกล้อง", category="กล้อง", price=80, type="hourly", **rates)


def test_an_item_keeps_every_rate_it_is_listed_with():
    item = _tripod(rates={"hourly": 80, "daily": 300})

    assert item.units == {"hourly", "daily"}
    assert item.rate("daily") == 300
    assert item.rate("weekly") is None


def test_a_budget_matches_the_rate_of_the_requested_period():
    item = _tripod(rates={"hourly": 80, "daily": 300})

    # เรตหลักเป็นรายชั่วโมง แต่งบรายวันต้องเทียบกับราคารายวัน
    assert item.fits_budget(["daily"], 350)
    assert not item.fits_budget(["daily"], 250)
    assert item.fits_budget(["hourly"], 80)
    assert not item.fits_budget(["weekly"], 10_000)


def test_an_item_without_explicit_rates_uses_its_primary_price():
    item = _tripod()

    assert item.rates == {"hourly": 80}
    assert item.units == {"hourly"}
