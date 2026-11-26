import 'dart:async';

import '../cache/app_cache.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session_validator.dart';
import 'supabase_client.dart';

enum AuthStartupState { guest, authenticated, loginRequired }

class AuthStartupResult {
  const AuthStartupResult(this.state, {this.oauthRestoreSession});

  final AuthStartupState state;
  final Session? oauthRestoreSession;
}

class AuthSession {
  AuthSession._();

  static String? _accessToken;
  static String? _authorizedUserId;
  static int _validationRevision = 0;

  static String? get accessToken {
    if (_accessToken == null) return null;
    if (SupabaseConfig.isInitialized) {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session == null ||
          session.accessToken != _accessToken ||
          session.user.appMetadata['dashboard_only'] == true ||
          (_authorizedUserId != null && session.user.id != _authorizedUserId)) {
        return null;
      }
      return session.accessToken;
    }
    return _accessToken;
  }

  static bool get isAuthenticated => accessToken != null;

  static Future<AuthStartupResult> restore({
    GoTrueClient? auth,
    AppSessionValidator? validator,
  }) async {
    final client =
        auth ??
        (SupabaseConfig.isInitialized ? SupabaseConfig.client.auth : null);
    final currentSession = client?.currentSession;
    if (client == null || currentSession == null) {
      return const AuthStartupResult(AuthStartupState.guest);
    }

    // OAuth ที่เปิดแอปกลับมาจะส่ง signedIn ส่วนเซสชันที่บันทึกไว้ส่ง initialSession
    String? oauthAccessToken;
    final observer = client.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn && !state.fromBroadcast) {
        oauthAccessToken = state.session?.accessToken;
      }
    }, onError: (Object _) {});
    Session? session;

    try {
      session = currentSession.isExpired
          ? (await client.refreshSession()).session
          : currentSession;
      if (session == null || session.isExpired) {
        clear();
        return const AuthStartupResult(AuthStartupState.guest);
      }
      await accept(session, validator: validator);
      return const AuthStartupResult(AuthStartupState.authenticated);
    } on AccountDeletionPending {
      if (session != null && oauthAccessToken == session.accessToken) {
        return AuthStartupResult(
          AuthStartupState.loginRequired,
          oauthRestoreSession: session,
        );
      }
      await reject(auth: client, userId: session?.user.id);
      return const AuthStartupResult(AuthStartupState.loginRequired);
    } on AccountDeletionExpired {
      await reject(auth: client, userId: session?.user.id);
      return const AuthStartupResult(AuthStartupState.loginRequired);
    } on AppSessionException catch (error) {
      clear();
      if (error.rejected) await reject(auth: client, userId: session?.user.id);
      return const AuthStartupResult(AuthStartupState.guest);
    } catch (_) {
      clear();
      return const AuthStartupResult(AuthStartupState.guest);
    } finally {
      await observer.cancel();
    }
  }

  static Future<void> accept(
    Session session, {
    AppSessionValidator? validator,
  }) async {
    clear();
    final revision = _validationRevision;
    final checker = validator ?? AppSessionValidator();
    try {
      await checker.validate(session);
      if (revision != _validationRevision ||
          (SupabaseConfig.isInitialized &&
              SupabaseConfig.client.auth.currentSession?.accessToken !=
                  session.accessToken)) {
        throw const AppSessionException('เซสชันเปลี่ยน กรุณาเข้าสู่ระบบใหม่');
      }
      _authorizedUserId = session.user.id;
      saveAccessToken(session.accessToken);
    } finally {
      if (validator == null) checker.close();
    }
  }

  static Future<void> reject({GoTrueClient? auth, String? userId}) async {
    if (userId != null && userId != _authorizedUserId) {
      unawaited(AppCache.forgetUser(userId));
    }
    clear(purgeCache: true);
    final client =
        auth ??
        (SupabaseConfig.isInitialized ? SupabaseConfig.client.auth : null);
    if (client != null) {
      try {
        await client.signOut(scope: SignOutScope.local);
      } catch (_) {
        // การปฏิเสธสิทธิ์ในแอปยังมีผล แม้คำขอออกจากระบบขัดข้อง
      }
    }
  }

  static void saveAccessToken(String token) {
    _accessToken = token;
  }

  static void clear({bool purgeCache = false}) {
    _validationRevision++;
    final userId = _authorizedUserId;
    if (purgeCache && userId != null) unawaited(AppCache.forgetUser(userId));
    _accessToken = null;
    _authorizedUserId = null;
  }
}
