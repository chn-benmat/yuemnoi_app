import 'package:shared_preferences/shared_preferences.dart';

/// ติดตามสถานะคำขอเช่าที่ได้รับการกดยืนยันแล้วในแอป (แยกตามข้อความแชท)
class BookingConfirmationTracker {
  BookingConfirmationTracker._();

  static final Set<String> _inMemoryConfirmedMessageIds = {};
  static final Map<String, int> _inMemoryBookingIds = {};

  static String formatOrderNumber(int? id) {
    if (id == null || id <= 0) return 'YM-NEW';
    return 'YM-${id.toString().padLeft(5, '0')}';
  }

  static int? getCachedBookingId(String messageId) {
    final trimmedId = messageId.trim();
    return _inMemoryBookingIds[trimmedId];
  }

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

  static final Map<String, String> _inMemoryStatuses = {};

  /// บันทึกสถานะคำขอเช่า เช่น 'pending', 'confirmed', 'active', 'completed'
  static Future<void> setStatus({
    required String messageId,
    required String status,
  }) async {
    final trimmedId = messageId.trim();
    if (trimmedId.isEmpty) return;

    _inMemoryStatuses[trimmedId] = status;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('booking_status_msg_$trimmedId', status);
    } catch (_) {}
  }

  /// ดึงสถานะของคำขอเช่า
  static Future<String?> getStatus({required String messageId}) async {
    final trimmedId = messageId.trim();
    if (trimmedId.isEmpty) return null;

    if (_inMemoryStatuses.containsKey(trimmedId)) {
      return _inMemoryStatuses[trimmedId];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final status = prefs.getString('booking_status_msg_$trimmedId');
      if (status != null && status.isNotEmpty) {
        _inMemoryStatuses[trimmedId] = status;
        return status;
      }
    } catch (_) {}
    return null;
  }

  /// บันทึกว่าการเช่าเริ่มใช้งานแล้ว (active)
  static Future<void> markActive({
    required String messageId,
    int? bookingId,
  }) async {
    final trimmedId = messageId.trim();
    if (trimmedId.isEmpty) return;

    await markConfirmed(messageId: trimmedId, bookingId: bookingId);
    await setStatus(messageId: trimmedId, status: 'active');
  }

  /// ตรวจสอบว่ารายการเช่านี้กำลังใช้งานอยู่ (active) หรือไม่
  static Future<bool> isRentalActive({required String messageId}) async {
    final status = await getStatus(messageId: messageId);
    return status == 'active';
  }

  /// ล้างสถานะการยืนยันของข้อความ (กรณีต้องการรีเซ็ต)
  static Future<void> unmarkConfirmed(String messageId) async {
    final trimmedId = messageId.trim();
    _inMemoryConfirmedMessageIds.remove(trimmedId);
    _inMemoryBookingIds.remove(trimmedId);
    _inMemoryStatuses.remove(trimmedId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('booking_confirmed_msg_$trimmedId');
      await prefs.remove('booking_id_msg_$trimmedId');
      await prefs.remove('booking_status_msg_$trimmedId');
    } catch (_) {}
  }

  /// ล้างแคชในหน่วยความจำทั้งหมด
  static void clearMemoryCache() {
    _inMemoryConfirmedMessageIds.clear();
    _inMemoryBookingIds.clear();
    _inMemoryStatuses.clear();
  }
}
