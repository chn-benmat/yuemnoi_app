import 'package:shared_preferences/shared_preferences.dart';

/// ติดตามสถานะคำขอเช่าที่ได้รับการกดยืนยันแล้วในแอป (แยกตามข้อความแชท)
class BookingConfirmationTracker {
  BookingConfirmationTracker._();

  static final Set<String> _inMemoryConfirmedMessageIds = {};

  /// บันทึกว่าข้อความคำขอเช่านี้ (messageId) ได้รับการกดยืนยันเรียบร้อยแล้ว
  static Future<void> markConfirmed({
    required String messageId,
    int? itemId,
  }) async {
    final trimmedId = messageId.trim();
    if (trimmedId.isEmpty) return;

    _inMemoryConfirmedMessageIds.add(trimmedId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('booking_confirmed_msg_$trimmedId', true);
    } catch (_) {}
  }

  /// ตรวจสอบว่าข้อความคำขอเช่านี้ (messageId) ได้รับการกดยืนยันแล้วหรือไม่
  static Future<bool> isConfirmed({
    required String messageId,
    int? itemId,
  }) async {
    final trimmedId = messageId.trim();
    if (trimmedId.isEmpty) return false;

    if (_inMemoryConfirmedMessageIds.contains(trimmedId)) {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('booking_confirmed_msg_$trimmedId') == true) {
        _inMemoryConfirmedMessageIds.add(trimmedId);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// ล้างสถานะการยืนยันของข้อความ (กรณีต้องการรีเซ็ต)
  static Future<void> unmarkConfirmed(String messageId) async {
    final trimmedId = messageId.trim();
    _inMemoryConfirmedMessageIds.remove(trimmedId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('booking_confirmed_msg_$trimmedId');
    } catch (_) {}
  }

  /// ล้างแคชในหน่วยความจำทั้งหมด
  static void clearMemoryCache() {
    _inMemoryConfirmedMessageIds.clear();
  }
}
