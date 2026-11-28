import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/navigation/app_routes.dart';
import 'core/network/auth_session.dart';
import 'core/network/supabase_client.dart';
import 'core/services/app_orientation_service.dart';
import 'core/services/chat_notification_service.dart';

import 'core/services/chat_pin_service.dart';
import 'core/services/favorite_service.dart';
import 'core/services/skeleton_layout_cache.dart';
import 'core/services/user_presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppOrientationService.setupOrientation();

  try {
    await initializeDateFormatting('th', null);
  } catch (_) {}

  try {
    await dotenv.load(fileName: '.env.local');
  } catch (_) {}

  try {
    final prefs = await SharedPreferences.getInstance();
    var apiUrl = AppConfig.apiUrl;
    if (apiUrl.isNotEmpty) {
      if (kIsWeb && apiUrl.contains('10.0.2.2')) {
        apiUrl = apiUrl.replaceAll('10.0.2.2', 'localhost');
      }
      await prefs.setString('api_url', apiUrl);
    }
  } catch (_) {}

  // โหลดรูปร่างหน้าที่เคยแสดง เพื่อให้ skeleton แรกตรงกับข้อมูลจริง
  await SkeletonLayoutCache.instance.init();
  await SupabaseConfig.initialize();
  unawaited(ChatPinService.instance.init());

  final startupAuth = await AuthSession.restore();
  unawaited(FavoriteService.instance.init(forceRefresh: true));
  if (startupAuth.state == AuthStartupState.authenticated) {
    UserPresenceService.instance.initialize();
  }

  await ChatNotificationService.instance.initialize();

  runApp(
    YuemnoiApp(
      initialRoute: startupAuth.state == AuthStartupState.loginRequired
          ? AppRoutes.login
          : AppRoutes.home,
      oauthRestoreSession: startupAuth.oauthRestoreSession,
    ),
  );
}
