import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/navigation/app_routes.dart';
import 'core/network/auth_session.dart';
import 'core/network/supabase_client.dart';
import 'core/services/app_orientation_service.dart';

import 'core/services/chat_notification_service.dart';
import 'core/services/chat_pin_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/user_presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppOrientationService.setupOrientation(); // บังคับแนวตั้งสำหรับโทรศัพท์ และอนุญาตแนวนอน/แนวตั้งสำหรับแท็บเล็ต/iPad

  try {
    await initializeDateFormatting('th', null);
  } catch (_) {}

  await dotenv.load(fileName: '.env.local');

  try {
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = dotenv.env['API_URL'];
    if (apiUrl != null && apiUrl.isNotEmpty) {
      await prefs.setString('api_url', apiUrl);
    }
  } catch (_) {}

  await SupabaseConfig.initialize();
  unawaited(ChatPinService.instance.init());

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FcmService.instance.initialize();
  } catch (e) {
    debugPrint('Firebase init warning: $e');
  }

  final isAuthenticated = await AuthSession.restore();
  if (isAuthenticated) {
    UserPresenceService.instance.initialize();
    unawaited(ChatNotificationService.instance.initialize());
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      unawaited(FcmService.instance.syncUserToken(userId));
    }
  }

  runApp(
    YuemnoiApp(
      initialRoute: isAuthenticated ? AppRoutes.home : AppRoutes.login,
    ),
  );
}
