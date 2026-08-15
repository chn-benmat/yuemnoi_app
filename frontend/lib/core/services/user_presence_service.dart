import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/supabase_client.dart';

class UserPresenceService with WidgetsBindingObserver {
  UserPresenceService._();
  static final UserPresenceService instance = UserPresenceService._();

  Timer? _heartbeatTimer;
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
    setOnline();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // อัปเดต Heartbeat ทุกๆ 45 วินาที
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _updatePresence(isOnline: true);
    });
  }

  Future<void> setOnline() async {
    await _updatePresence(isOnline: true);
  }

  Future<void> setOffline() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _updatePresence(isOnline: false);
  }

  Future<void> _updatePresence({required bool isOnline}) async {
    if (!SupabaseConfig.isInitialized) return;
    final client = SupabaseConfig.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    try {
      await client.from('profile_tb').update({
        'is_online': isOnline,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setOnline();
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setOffline();
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
  }
}
