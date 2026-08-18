import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../network/supabase_client.dart';
import 'chat_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    if (!dotenv.isInitialized) {
      await dotenv.load(fileName: '.env.local');
    }
    if (!SupabaseConfig.isInitialized) {
      await SupabaseConfig.initialize();
    }
  } catch (_) {}

  debugPrint('FCM Background Message Received: ${message.messageId} / Data: ${message.data}');

  final data = message.data;
  final type = data['type']?.toString() ?? '';

  if (type == 'chat_message' || type == 'chat') {
    final title = data['sender_name']?.toString() ??
        message.notification?.title ??
        data['title']?.toString() ??
        'ข้อความใหม่';
    final rawBody = data['message']?.toString() ??
        message.notification?.body ??
        data['body']?.toString() ??
        'ส่งข้อความถึงคุณ';
    final body = _extractCleanNotificationText(rawBody);
    final conversationId = data['conversation_id']?.toString() ?? '';
    final messageId = data['message_id']?.toString() ?? message.messageId ?? '';

    await ChatNotificationService.instance.showSystemNotification(
      id: conversationId.isNotEmpty ? conversationId.hashCode : message.hashCode,
      title: title,
      body: body,
      payload: conversationId,
      messageId: messageId,
    );
  }
}

/// สกัดเอาเฉพาะข้อความตอบกลับตัวจริง โดยตัดคำนำหน้า '↩ ตอบกลับ:...' ออก
String _extractCleanNotificationText(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'ส่งข้อความถึงคุณ';
  if (trimmed.startsWith('↩ ตอบกลับ:') ||
      trimmed.startsWith('💬 ตอบกลับ') ||
      trimmed.startsWith('↪ ตอบกลับ')) {
    final newlineIdx = trimmed.indexOf('\n');
    if (newlineIdx != -1) {
      final actual = trimmed.substring(newlineIdx + 1).trim();
      return actual.isNotEmpty ? actual : 'ส่งข้อความถึงคุณ';
    }
    final pipeParts = trimmed.split('|');
    if (pipeParts.length >= 2) {
      final actual = pipeParts[1].trim();
      return actual.isNotEmpty ? actual : 'ส่งข้อความถึงคุณ';
    }
  }
  return trimmed;
}



class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _isInitialized = false;
  String? _cachedToken;

  /// ขอสิทธิ์การแจ้งเตือนจาก Firebase Cloud Messaging
  Future<NotificationSettings?> requestNotificationPermission() async {
    try {
      final messaging = FirebaseMessaging.instance;
      return await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );
    } catch (e) {
      debugPrint('FCM requestPermission error: $e');
      return null;
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();

      final messaging = FirebaseMessaging.instance;

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // จัดการ Message เมื่อเปิดแอปค้างไว้ (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleForegroundMessage(message);
      });

      // จัดการเมื่อแตะการแจ้งเตือนเพื่อเปิดแอป
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleMessageOpenedApp(message);
      });

      // ฟังการเปลี่ยนแปลง Token
      messaging.onTokenRefresh.listen((newToken) {
        _cachedToken = newToken;
        _saveTokenToSupabase(newToken);
      });

      // ดึง Token ปัจจุบัน
      _cachedToken = await messaging.getToken();
      if (_cachedToken != null) {
        _saveTokenToSupabase(_cachedToken!);
      }

      // ตรวจสอบการเปิดแอปจากการกดแจ้งเตือนขณะแอปถูกปิด (Terminated)
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      _isInitialized = true;
      debugPrint('FCM Initialized successfully. Token: $_cachedToken');
    } catch (e) {
      debugPrint('FCM Initialization error: $e');
    }
  }

  Future<void> syncUserToken(String userId) async {
    if (userId.isEmpty) return;
    try {
      final token = _cachedToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
        await _saveTokenToSupabaseWithUserId(token, userId);
      }
    } catch (e) {
      debugPrint('Sync FCM token error: $e');
    }
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      if (!SupabaseConfig.isInitialized) return;
      final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        await _saveTokenToSupabaseWithUserId(token, currentUserId);
      }
    } catch (_) {}
  }

  Future<void> _saveTokenToSupabaseWithUserId(String token, String userId) async {
    try {
      if (!SupabaseConfig.isInitialized) return;
      await SupabaseConfig.client
          .from('profile_tb')
          .update({'fcm_token': token})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Save FCM token to Supabase error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM Foreground Message: ${message.data}');
  }


  void _handleMessageOpenedApp(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString() ?? '';

    if (type == 'chat' || type == 'chat_message') {
      final conversationId = data['conversation_id']?.toString() ?? '';
      if (conversationId.isNotEmpty) {
        ChatNotificationService.instance.onNotificationTapped?.call(conversationId);
      }
    }
  }
}

