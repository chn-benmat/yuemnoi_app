import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseConfig {
  static const oauthRedirectUrl = 'yuemnoi://login-callback/';

  static bool _isInitialized = false;

  static String get projectUrl => dotenv.env['SUPABASE_URL']?.trim() ?? '';

  static String get clientKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY']?.trim() ?? '';

  static bool get isConfigured => projectUrl.isNotEmpty && clientKey.isNotEmpty;

  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    if (!isConfigured) return;

    await Supabase.initialize(url: projectUrl, publishableKey: clientKey);
    _isInitialized = true;
  }

  static SupabaseClient get client {
    if (!_isInitialized) {
      throw StateError(
        'Supabase is not configured. Check SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY in .env.local.',
      );
    }
    return Supabase.instance.client;
  }
}
