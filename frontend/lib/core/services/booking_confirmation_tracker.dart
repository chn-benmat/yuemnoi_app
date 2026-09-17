import 'package:shared_preferences/shared_preferences.dart';

/// ติดตามสถานะคำขอเช่าที่ได้รับการกดยืนยันแล้วในแอป (แยกตามข้อความแชท)
class BookingConfirmationTracker {
  BookingConfirmationTracker._();

  static final Set<String> _inMemoryConfirmedMessageIds = {};
  static final Map<String, int> _inMemoryBookingIds = {};

  /// บันทึกว่าข้อความคำขอเช่านี้ (messageId) ได้รับการกดยืนยันเรียบร้อยแล้ว
  static Future<void> markConfirmed({
    required String messageId,
    int? itemId,
    int? bookingId,
  }) async {
    final trimmedId = messageId.trim();
    if (trimmedId.isEmpty) return;

    _inMemoryConfirmedMessageIds.add(trimmedId);
    if (bookingId != null && bookingId > 0) {
      _inMemoryBookingIds[trimmedId] = bookingId;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('booking_confirmed_msg_$trimmedId', true);
      if (bookingId != null && bookingId > 0) {
        await prefs.setInt('booking_id_msg_$trimmedId', bookingId);
      }
    } catch (_) {}
  }

  /// ดึง bookingId ที่ผูกกับข้อความคำขอเช่านี้ (ถ้ามี)
  static Future<int?> getBookingId({required String messageId}) async {
    final trimmedId = messageId.trim();
    if (trimmedId.isEmpty) return null;

    if (_inMemoryBookingIds.containsKey(trimmedId)) {
      return _inMemoryBookingIds[trimmedId];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt('booking_id_msg_$trimmedId');
      if (id != null && id > 0) {
        _inMemoryBookingIds[trimmedId] = id;
        return id;
      }
    } catch (_) {}
    return null;
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
    _inMemoryBookingIds.remove(trimmedId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('booking_confirmed_msg_$trimmedId');
      await prefs.remove('booking_id_msg_$trimmedId');
    } catch (_) {}
  }

  /// ล้างแคชในหน่วยความจำทั้งหมด
  static void clearMemoryCache() {
    _inMemoryConfirmedMessageIds.clear();
    _inMemoryBookingIds.clear();
  }
}
