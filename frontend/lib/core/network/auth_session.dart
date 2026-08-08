import 'supabase_client.dart';

class AuthSession {
  AuthSession._();

  static String? _accessToken;

  static String? get accessToken {
    if (SupabaseConfig.isInitialized) {
      return SupabaseConfig.client.auth.currentSession?.accessToken ??
          _accessToken;
    }
    return _accessToken;
  }

  static bool get isAuthenticated => accessToken != null;

  static Future<bool> restore() async {
    if (!SupabaseConfig.isInitialized) return false;

    final currentSession = SupabaseConfig.client.auth.currentSession;
    if (currentSession == null) return false;

    if (!currentSession.isExpired) {
      saveAccessToken(currentSession.accessToken);
      return true;
    }

    try {
      final response = await SupabaseConfig.client.auth.refreshSession();
      final refreshedSession = response.session;
      if (refreshedSession == null || refreshedSession.isExpired) {
        return false;
      }

      saveAccessToken(refreshedSession.accessToken);
      return true;
    } catch (_) {
      _accessToken = null;
      return false;
    }
  }

  static void saveAccessToken(String token) {
    _accessToken = token;
  }

  static void clear() {
    _accessToken = null;
  }
}
