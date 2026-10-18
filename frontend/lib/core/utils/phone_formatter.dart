import 'package:phone_numbers_parser/phone_numbers_parser.dart';

abstract final class PhoneFormatter {
  /// แปลงเบอร์โทรให้ขึ้นต้นด้วย 0 สำหรับแสดงผลในหน้าจอโปรไฟล์และแอป (เช่น '+66812345678' -> '0812345678')
  static String formatForDisplay(String? phone) {
    final number = _parseThaiPhone(phone);
    return number == null ? (phone?.trim() ?? '') : '0${number.nsn}';
  }

  /// แปลงเบอร์โทรให้ขึ้นต้นด้วย +66 สำหรับบันทึกลงใน Supabase (เช่น '0812345678' -> '+66812345678')
  static String formatForSupabase(String? phone) {
    return _parseThaiPhone(phone)?.international ?? (phone?.trim() ?? '');
  }

  /// ตรวจสอบว่าเบอร์โทรเป็นรูปแบบที่ถูกต้องหรือไม่ (รองรับทั้ง 0xxxxxxxxx, +66xxxxxxxxx, 66xxxxxxxxx)
  static bool isValidPhone(String? phone) {
    final number = _parseThaiPhone(phone);
    // ฟอร์มเดิมใช้เบอร์ไทยสิบหลัก จึงไม่ขยายไปยังเบอร์สั้นหรือประเทศอื่น
    return number != null && number.nsn.length == 9;
  }

  static String formatForDialer(String phone) {
    try {
      final number = PhoneNumber.parse(phone, callerCountry: IsoCode.TH);
      if (number.isValid()) {
        return number.isoCode == IsoCode.TH
            ? '0${number.nsn}'
            : number.international;
      }
    } on PhoneNumberException {
      // คงเบอร์สั้นและค่าที่นำเข้าจากแชทเดิมไว้ให้แอปโทรศัพท์เป็นผู้จัดการ
    }
    return phone.trim().replaceAll(RegExp(r'[\s()-]'), '');
  }

  static PhoneNumber? _parseThaiPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    try {
      final number = PhoneNumber.parse(phone, callerCountry: IsoCode.TH);
      return number.isoCode == IsoCode.TH && number.isValid() ? number : null;
    } on PhoneNumberException {
      return null;
    }
  }
}
