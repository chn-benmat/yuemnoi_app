import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/supabase_client.dart';

class UserPresenceService with WidgetsBindingObserver {
  UserPresenceService._();
  static final UserPresenceService instance = UserPresenceService._();

  Timer? _heartbeatTimer;
  bool _isInitialized = false;
  RealtimeChannel? _presenceChannel;

  /// รายชื่อ User ID ของผู้ที่กำลังออนไลน์อยู่ในขณะนี้แบบ Real-time
  final ValueNotifier<Set<String>> onlineUsersNotifier =
      ValueNotifier<Set<String>>({});

  bool isUserOnline(String userId) {
    if (userId.isEmpty) return false;
    return onlineUsersNotifier.value.contains(userId);
  }

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
    _initPresenceChannel();
    setOnline();
    _startHeartbeat();
  }

  void _initPresenceChannel() {
    if (!SupabaseConfig.isInitialized) return;
    try {
      final client = SupabaseConfig.client;
      _presenceChannel = client.channel('global_presence');

      _presenceChannel?.onPresenceSync((_) {
        final presenceState = _presenceChannel?.presenceState();
        if (presenceState != null) {
          final activeSet = <String>{};
          for (final entry in presenceState) {
            for (final presence in entry.presences) {
              final payload = presence.payload;
              final uid = payload['user_id'] as String?;
              final isOnline = payload['is_online'] as bool? ?? false;
              if (uid != null && uid.isNotEmpty && isOnline) {
                activeSet.add(uid);
              }
            }
          }
          onlineUsersNotifier.value = activeSet;
        }
      });

      _presenceChannel?.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _trackPresence(isOnline: true);
        }
      });
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // อัปเดต Heartbeat ทุกๆ 45 วินาที
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _updatePresence(isOnline: true);
      _trackPresence(isOnline: true);
    });
  }

  Future<void> setOnline() async {
    await _updatePresence(isOnline: true);
    await _trackPresence(isOnline: true);
  }

  Future<void> setOffline() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _trackPresence(isOnline: false);
    await _updatePresence(isOnline: false);
  }

  Future<void> _trackPresence({required bool isOnline}) async {
    if (!SupabaseConfig.isInitialized || _presenceChannel == null) return;
    final client = SupabaseConfig.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    try {
      if (isOnline) {
        await _presenceChannel?.track({
          'user_id': userId,
          'is_online': true,
          'last_active': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await _presenceChannel?.untrack();
      }
    } catch (_) {}
  }

  Future<void> _updatePresence({required bool isOnline}) async {
    if (!SupabaseConfig.isInitialized) return;
    final client = SupabaseConfig.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    try {
      await client
          .schema('profiles')
          .from('profile_tb')
          .update({
            'is_online': isOnline,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // เปิดแอปใช้งานอยู่ -> Online
      setOnline();
      _startHeartbeat();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // ออกจากแอป / สลับแอป / พับหน้าจอไว้ แต่ยังไม่ปัดแอปทิ้ง -> ยังคง Online อยู่
      setOnline();
    } else if (state == AppLifecycleState.detached) {
      // ปัดแอปทิ้ง (Kill App) / ปิดโปรแกรม -> Offline ทันที
      setOffline();
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      _presenceChannel?.unsubscribe();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
  }
}
