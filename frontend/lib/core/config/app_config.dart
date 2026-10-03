import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AppConfig เป็นศูนย์รวมการอ่านค่าคอนฟิกูเรชันของระบบ Frontend
/// รองรับทั้งการ Compile แบบปลอดภัยด้วย --dart-define-from-file=.env.local
/// และมี Fallback ไปยัง dotenv สำหรับสภาพแวดล้อมที่จำเป็น
abstract final class AppConfig {
  static const String _envApiUrl = String.fromEnvironment('API_URL');
  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envSupabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _envAppSecretKey =
      String.fromEnvironment('APP_SECRET_KEY');
  static const String _envGoogleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static String get apiUrl {
    if (_envApiUrl.isNotEmpty) return _envApiUrl;
    if (dotenv.isInitialized) return dotenv.env['API_URL']?.trim() ?? '';
    return '';
  }

  static String get supabaseUrl {
    if (_envSupabaseUrl.isNotEmpty) return _envSupabaseUrl;
    if (dotenv.isInitialized) return dotenv.env['SUPABASE_URL']?.trim() ?? '';
    return '';
  }

  static String get supabasePublishableKey {
    if (_envSupabasePublishableKey.isNotEmpty) return _envSupabasePublishableKey;
    if (dotenv.isInitialized) return dotenv.env['SUPABASE_PUBLISHABLE_KEY']?.trim() ?? '';
    return '';
  }

  static String get appSecretKey {
    final key = _envAppSecretKey.isNotEmpty
        ? _envAppSecretKey
        : (dotenv.isInitialized ? (dotenv.env['APP_SECRET_KEY']?.trim() ?? '') : '');
    if (kDebugMode && key.isEmpty) {
      debugPrint('[SECURITY WARNING] APP_SECRET_KEY is empty in frontend environment.');
    }
    return key;
  }

  static String get googleWebClientId {
    if (_envGoogleWebClientId.isNotEmpty) return _envGoogleWebClientId;
    if (dotenv.isInitialized) return dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim() ?? '';
    return '';
  }
}
