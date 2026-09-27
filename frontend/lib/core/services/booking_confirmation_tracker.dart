import 'package:shared_preferences/shared_preferences.dart';

/// ติดตามสถานะคำขอเช่าที่ได้รับการกดยืนยันแล้วในแอป (แยกตามข้อความแชท)
class BookingConfirmationTracker {
  BookingConfirmationTracker._();

  static final Set<String> _inMemoryConfirmedMessageIds = {};
  static final Map<String, int> _inMemoryBookingIds = {};
  static final Map<String, DateTime> _inMemoryHandoverStartTimes = {};

  /// บันทึกเวลาที่เริ่มส่งมอบจริง (Handover Started)
  static Future<void> markHandoverStarted({
    int? bookingId,
    String? messageId,
    DateTime? startTime,
  }) async {
    final time = startTime ?? DateTime.now();
    if (bookingId != null && bookingId > 0) {
      _inMemoryHandoverStartTimes['b_$bookingId'] = time;
    }
    if (messageId != null && messageId.trim().isNotEmpty) {
      _inMemoryHandoverStartTimes['m_${messageId.trim()}'] = time;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final iso = time.toIso8601String();
      if (bookingId != null && bookingId > 0) {
        await prefs.setString('handover_start_b_$bookingId', iso);
      }
      if (messageId != null && messageId.trim().isNotEmpty) {
        await prefs.setString('handover_start_m_${messageId.trim()}', iso);
      }
    } catch (_) {}
  }

  /// ดึงเวลาเริ่มส่งมอบจาก Memory ทันที (Synchronous)
  static DateTime? getHandoverStartTimeSync({
    int? bookingId,
    String? messageId,
  }) {
    if (bookingId != null &&
        bookingId > 0 &&
        _inMemoryHandoverStartTimes.containsKey('b_$bookingId')) {
      return _inMemoryHandoverStartTimes['b_$bookingId'];
    }
    if (messageId != null &&
        messageId.trim().isNotEmpty &&
        _inMemoryHandoverStartTimes.containsKey('m_${messageId.trim()}')) {
      return _inMemoryHandoverStartTimes['m_${messageId.trim()}'];
    }
    return null;
  }

  /// ดึงเวลาเริ่มส่งมอบแบบ Asynchronous (ตรวจ SharedPreferences ด้วย)
  static Future<DateTime?> getHandoverStartTime({
    int? bookingId,
    String? messageId,
  }) async {
    final cached = getHandoverStartTimeSync(
      bookingId: bookingId,
      messageId: messageId,
    );
    if (cached != null) return cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (bookingId != null && bookingId > 0) {
        final raw = prefs.getString('handover_start_b_$bookingId');
        if (raw != null) {
          final dt = DateTime.tryParse(raw);
          if (dt != null) {
            _inMemoryHandoverStartTimes['b_$bookingId'] = dt;
            return dt;
          }
        }
      }
      if (messageId != null && messageId.trim().isNotEmpty) {
        final raw = prefs.getString('handover_start_m_${messageId.trim()}');
        if (raw != null) {
          final dt = DateTime.tryParse(raw);
          if (dt != null) {
            _inMemoryHandoverStartTimes['m_${messageId.trim()}'] = dt;
            return dt;
          }
        }
      }
    } catch (_) {}
    return null;
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

  /// ล้างสถานะการยืนยันของข้อความ (กรณีต้องการรีเซ็ต)
  static Future<void> unmarkConfirmed(String messageId) async {
    final trimmedId = messageId.trim();
    _inMemoryConfirmedMessageIds.remove(trimmedId);
    _inMemoryBookingIds.remove(trimmedId);
    _inMemoryHandoverStartTimes.remove('m_$trimmedId');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('booking_confirmed_msg_$trimmedId');
      await prefs.remove('booking_id_msg_$trimmedId');
      await prefs.remove('handover_start_m_$trimmedId');
    } catch (_) {}
  }

  /// ล้างแคชในหน่วยความจำทั้งหมด
  static void clearMemoryCache() {
    _inMemoryConfirmedMessageIds.clear();
    _inMemoryBookingIds.clear();
    _inMemoryHandoverStartTimes.clear();
  }
}
