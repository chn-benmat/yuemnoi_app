import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/chat_conversation.dart';

class ChatRentalSafetyPreferences {
  const ChatRentalSafetyPreferences({DateTime Function() now = DateTime.now})
    : _now = now;

  final DateTime Function() _now;

  String _key(String accountId, ChatParticipantRole role) =>
      'chat_rental_safety_hidden_day.${role.name}.$accountId';

  int get _today {
    final local = _now().toLocal();
    return local.year * 10000 + local.month * 100 + local.day;
  }

  Future<bool> isHiddenToday(String accountId, ChatParticipantRole role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_key(accountId, role)) == _today;
    } catch (_) {
      return false;
    }
  }

  Future<void> hideToday(String accountId, ChatParticipantRole role) async {
    final today = _today;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(accountId, role), today);
    } catch (_) {
      // การบันทึกการซ่อนขัดข้องได้ แต่ผู้ใช้ยังต้องเข้าแชทต่อได้
    }
  }
}
