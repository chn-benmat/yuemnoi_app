import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/auth_session.dart';
import '../../data/notification_remote_data_source.dart';
import '../../domain/app_notification.dart';

/// จุดแดงที่ไอคอนแจ้งเตือนใน navbar: true เมื่อมีแจ้งเตือนใหม่กว่าครั้งล่าสุดที่ผู้ใช้เปิดแท็บแจ้งเตือน
class NotificationBadgeCubit extends Cubit<bool> {
  NotificationBadgeCubit({
    NotificationRemoteDataSource? source,
    Future<SharedPreferences> Function()? prefs,
  }) : _source = source,
       _prefs = prefs ?? SharedPreferences.getInstance,
       super(false);

  NotificationRemoteDataSource? _source;
  final Future<SharedPreferences> Function() _prefs;
  int _request = 0;

  static String _key(String userId) => 'notification_last_seen.$userId';

  /// ดึงแจ้งเตือนล่าสุดหนึ่งรายการแล้วเทียบกับเวลาที่เปิดดูครั้งล่าสุด
  Future<void> check() async {
    final request = ++_request;
    final userId = AuthSession.userId;
    final token = AuthSession.accessToken;
    if (userId == null || token == null) {
      if (!isClosed) emit(false);
      return;
    }
    try {
      final latest = await _latest(token);
      final prefs = await _prefs();
      if (isClosed || request != _request || AuthSession.userId != userId) {
        return;
      }
      if (latest == null) return emit(false);
      final seen = DateTime.tryParse(prefs.getString(_key(userId)) ?? '');
      // ยังไม่เคยเปิดแท็บในเครื่องนี้ ให้แสดงจุดเฉพาะเมื่อรายการล่าสุดยังไม่อ่าน
      emit(
        seen == null
            ? !latest.isRead
            : latest.updatedAt != null && latest.updatedAt!.isAfter(seen),
      );
    } catch (_) {
      // โหลดไม่สำเร็จให้คงสถานะเดิม จะตรวจใหม่เมื่อมี push หรือกลับเข้าแอป
    }
  }

  /// เรียกเมื่อผู้ใช้อยู่ในแท็บแจ้งเตือน: ซ่อนจุดและจำเวลาของรายการล่าสุดไว้
  Future<void> markSeen() async {
    ++_request;
    if (!isClosed) emit(false);
    final userId = AuthSession.userId;
    final token = AuthSession.accessToken;
    if (userId == null || token == null) return;
    try {
      final latest = await _latest(token);
      // ใช้เวลาจาก server แทนนาฬิกาเครื่อง เพื่อไม่ให้เวลาเครื่องคลาดทำให้จุดไม่ขึ้น
      final seenAt = latest?.updatedAt ?? DateTime.now().toUtc();
      final prefs = await _prefs();
      if (AuthSession.userId != userId) return;
      await prefs.setString(_key(userId), seenAt.toIso8601String());
    } catch (_) {
      // บันทึกไม่สำเร็จ จุดอาจกลับมาในการตรวจครั้งถัดไป ซึ่งยอมรับได้
    }
  }

  Future<AppNotification?> _latest(String token) async {
    final items = await (_source ??= NotificationRemoteDataSource()).fetch(
      token,
      limit: 1,
      offset: 0,
    );
    return items.isEmpty ? null : items.first;
  }

  @override
  Future<void> close() {
    _source?.close();
    return super.close();
  }
}
