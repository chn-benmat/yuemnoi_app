import 'dart:async';

import '../cache/app_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session_validator.dart';
import 'supabase_client.dart';

class AuthSession {
  AuthSession._();

  static String? _accessToken;
  static String? _authorizedUserId;

  static String? get accessToken {
    if (_accessToken == null) return null;
    if (SupabaseConfig.isInitialized) {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session == null ||
          session.user.appMetadata['dashboard_only'] == true ||
          (_authorizedUserId != null && session.user.id != _authorizedUserId)) {
        return null;
      }
      return session.accessToken;
    }
    return _accessToken;
  }

  static bool get isAuthenticated => accessToken != null;

  static Future<bool> restore() async {
    if (!SupabaseConfig.isInitialized) return false;

    final currentSession = SupabaseConfig.client.auth.currentSession;
    if (currentSession == null) return false;

    try {
      final session = currentSession.isExpired
          ? (await SupabaseConfig.client.auth.refreshSession()).session
          : currentSession;
      if (session == null || session.isExpired) {
        clear();
        return false;
      }
      await accept(session);
      return true;
    } on AppSessionException catch (error) {
      clear();
      if (error.rejected) await reject();
      return false;
    } catch (_) {
      clear();
      return false;
    }
  }

  static Future<void> accept(
    Session session, {
    AppSessionValidator? validator,
  }) async {
    clear();
    final checker = validator ?? AppSessionValidator();
    try {
      await checker.validate(session);
      _authorizedUserId = session.user.id;
      saveAccessToken(session.accessToken);
    } finally {
      if (validator == null) checker.close();
    }
  }

  static Future<void> reject() async {
    clear(purgeCache: true);
    if (SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // การปฏิเสธสิทธิ์ในแอปยังมีผล แม้คำขอออกจากระบบขัดข้อง
      }
    }
  }

  static void saveAccessToken(String token) {
    _accessToken = token;
  }

  static void clear({bool purgeCache = false}) {
    final userId = _authorizedUserId;
    if (purgeCache && userId != null) unawaited(AppCache.forgetUser(userId));
    _accessToken = null;
    _authorizedUserId = null;
  }
}
