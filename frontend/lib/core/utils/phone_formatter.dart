abstract final class PhoneFormatter {
  /// แปลงเบอร์โทรให้ขึ้นต้นด้วย 0 สำหรับแสดงผลในหน้าจอโปรไฟล์และแอป (เช่น '+66812345678' -> '0812345678')
  static String formatForDisplay(String? phone) {
    if (phone == null) return '';
    var clean = phone.trim();
    if (clean.startsWith('+66')) {
      return '0${clean.substring(3)}';
    } else if (clean.startsWith('66') && clean.length == 11) {
      return '0${clean.substring(2)}';
    }
    return clean;
  }

  /// แปลงเบอร์โทรให้ขึ้นต้นด้วย +66 สำหรับบันทึกลงใน Supabase (เช่น '0812345678' -> '+66812345678')
  static String formatForSupabase(String? phone) {
    if (phone == null) return '';
    var clean = phone.replaceAll(RegExp(r'\s+|-'), '').trim();
    if (clean.startsWith('+66')) {
      return clean;
    } else if (clean.startsWith('66') && clean.length == 11) {
      return '+$clean';
    } else if (clean.startsWith('0') && clean.length == 10) {
      return '+66${clean.substring(1)}';
    }
    return clean;
  }

  /// ตรวจสอบว่าเบอร์โทรเป็นรูปแบบที่ถูกต้องหรือไม่ (รองรับทั้ง 0xxxxxxxxx, +66xxxxxxxxx, 66xxxxxxxxx)
  static bool isValidPhone(String? phone) {
    if (phone == null) return false;
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 10 && digitsOnly.startsWith('0')) {
      return true;
    }
    if (digitsOnly.length == 11 && digitsOnly.startsWith('66')) {
      return true;
    }
    return false;
  }
}
