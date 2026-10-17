"""สร้างข้อมูลที่อยู่ในแอปจากต้นทางที่ตรึงเวอร์ชันไว้ เพื่อให้ตรวจสอบย้อนหลังได้"""

import json
from pathlib import Path
from urllib.request import urlopen


GEOGRAPHY_COMMIT = "b8b3fb91c7df1129ff5b43cb46f7fcffadd2156b"
POSTAL_COMMIT = "2f2737e560acc88e6bf1144e8fad3355a72d977d"
GEOGRAPHY_URL = (
    "https://raw.githubusercontent.com/thailand-geography-data/"
    f"thailand-geography-json/{GEOGRAPHY_COMMIT}"
)
POSTAL_URL = (
    "https://raw.githubusercontent.com/earthchie/"
    f"jquery.Thailand.js/{POSTAL_COMMIT}"
)
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "data"


def download(url: str) -> str:
    with urlopen(url, timeout=60) as response:
        return response.read().decode("utf-8-sig")


def main() -> None:
    geography = json.loads(download(f"{GEOGRAPHY_URL}/src/geography.json"))
    postal_rows = json.loads(
        download(f"{POSTAL_URL}/jquery.Thailand.js/database/raw_database/raw_database.json")
    )
    # เพิ่มรหัสทางเลือกเฉพาะชื่อพื้นที่ที่ตรงกันครบทั้งสามระดับ เพื่อไม่ย้ายรหัสข้ามเขต
    alternative_codes: dict[tuple[str, str, str], set[str]] = {}
    for row in postal_rows:
        key = (row["province"].strip(), row["amphoe"].strip(), row["district"].strip())
        code = str(row["zipcode"])
        if len(code) == 5 and code.isascii() and code.isdigit() and code[0] != "0":
            alternative_codes.setdefault(key, set()).add(code)

    provinces = {}
    districts = {}
    subdistrict_ids = set()
    for row in geography:
        province_id = row["provinceCode"]
        district_id = row["districtCode"]
        subdistrict_id = row["subdistrictCode"]
        if subdistrict_id in subdistrict_ids:
            raise ValueError(f"Duplicate subdistrict: {subdistrict_id}")
        subdistrict_ids.add(subdistrict_id)
        province = provinces.setdefault(
            province_id, {"id": province_id, "name": row["provinceNameTh"], "districts": []}
        )
        if district_id not in districts:
            districts[district_id] = {
                "id": district_id,
                "name": row["districtNameTh"],
                "subdistricts": [],
            }
            province["districts"].append(districts[district_id])
        key = (row["provinceNameTh"], row["districtNameTh"], row["subdistrictNameTh"])
        primary = str(row["postalCode"])
        codes = [primary, *sorted(alternative_codes.get(key, set()) - {primary})]
        if not all(len(code) == 5 and code.isdigit() for code in codes):
            raise ValueError(f"Invalid postal codes: {subdistrict_id}")
        districts[district_id]["subdistricts"].append(
            {"id": subdistrict_id, "name": row["subdistrictNameTh"], "postal_codes": codes}
        )

    if (len(provinces), len(districts), len(subdistrict_ids)) != (77, 928, 7436):
        raise ValueError("ตรวจจำนวนพื้นที่กับต้นทางใหม่ก่อนเปลี่ยนข้อมูลในแอป")
    data = {
        "sources": {
            "geography": f"https://github.com/thailand-geography-data/thailand-geography-json/tree/{GEOGRAPHY_COMMIT}",
            "additional_postal_codes": f"https://github.com/earthchie/jquery.Thailand.js/tree/{POSTAL_COMMIT}",
        },
        "provinces": sorted(provinces.values(), key=lambda province: province["id"]),
    }
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "thai_addresses.json").write_text(
        json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8"
    )
    (OUTPUT / "THIRD_PARTY_LICENSES.txt").write_text(
        "thailand-geography-data/thailand-geography-json\n"
        + download(f"{GEOGRAPHY_URL}/LICENSE")
        + "\n\nearthchie/jquery.Thailand.js\n"
        + download(f"{POSTAL_URL}/LICENSE"),
        encoding="utf-8",
    )
    multi = sum(
        len(subdistrict["postal_codes"]) > 1
        for district in districts.values()
        for subdistrict in district["subdistricts"]
    )
    print(f"77 provinces, 928 districts, 7436 subdistricts; {multi} with multiple postal codes")


if __name__ == "__main__":
    main()
