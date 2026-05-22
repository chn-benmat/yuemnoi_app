class IntentRouter:
    @staticmethod
    def check_needs_google_verification(user_query: str) -> bool:
        keywords_requiring_verification = [
            "สเปค",
            "spec",
            "ถ่าย 4k",
            "กันน้ำ",
            "เล่นเกม",
            "ไหวไหม",
            "รองรับ",
            "ของแท้ไหม",
            "คอนกรีต",
            "แท้หรือปลอม",
            "เวอร์ชันไหน",
        ]

        # แปลงข้อความเป็นตัวพิมพ์เล็กเพื่อความแม่นยำในการดักจับ
        lowered_query = user_query.lower()

        # คืนค่า True ทันทีหากตรวจพบคำค้นหาที่เสี่ยงต่อข้อมูลผิดพลาด ต้องรีเช็คบน Google
        return any(
            keyword in lowered_query for keyword in keywords_requiring_verification
        )
