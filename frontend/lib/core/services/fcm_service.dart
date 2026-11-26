import 'dart:async';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/auth_session.dart';
import '../network/notification_device_data_source.dart';
import '../network/supabase_client.dart';
import 'app_notification_service.dart';
import 'chat_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Backend ส่ง notification payload ให้ OS แสดงแล้ว จึงไม่สร้าง local ซ้ำจาก isolate
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();
  static const _iosNotifications = MethodChannel(
    'yuemnoi/foreground_notifications',
  );
  bool _isInitialized = false;
  Future<void>? _initializing;
  FirebaseMessaging? _messaging;
  String? _cachedToken;
  String? _userId;
  String? _registeredUser;
  String? _registeredToken;
  Future<String>? _installation;
  Timer? _retry;
  int _retryCount = 0;
  int _generation = 0;
  Future<void> _registrationQueue = Future.value();
  Future<void>? _unregistering;
  Map<String, dynamic>? _pendingTap;
  Future<void> Function(Map<String, dynamic>)? _onNotificationOpened;

  set onNotificationOpened(
    Future<void> Function(Map<String, dynamic>)? callback,
  ) {
    _onNotificationOpened = callback;
    if (callback != null) unawaited(flushPendingTap());
  }

  Future<void> initialize() {
    if (kIsWeb || _isInitialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _iosNotifications.setMethodCallHandler((call) async {
          final data = call.arguments;
          return call.method == 'shouldPresent' &&
              data is Map &&
              _canPresentForegroundUpdate(Map<String, dynamic>.from(data));
        });
      }
      final notifications = ChatNotificationService.instance;
      notifications.onPushNotificationTapped = _queueTap;
      notifications.onNotificationTapped = (conversationId) => _queueTap({
        'type': 'chat_message',
        'conversation_id': conversationId,
      });
      await notifications.initialize();
      await Firebase.initializeApp();
      final messaging = _messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _queueTap(message.data);
      });
      messaging.onTokenRefresh.listen((token) {
        _cachedToken = token;
        final userId = _userId;
        if (userId != null) unawaited(syncUserToken(userId));
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _pendingTap ??= Map<String, dynamic>.from(initial.data);
      }
      _isInitialized = true;
      unawaited(flushPendingTap());
    } catch (_) {
      // ไม่พิมพ์ token หรือข้อความลง log และให้การ sync ครั้งถัดไปเริ่มใหม่ได้
      debugPrint(
        'FCM: initialization unavailable; retry on authenticated sync',
      );
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    if (data['category'] == 'chat' || data['type'] == 'chat_message') {
      if (_belongsToCurrentUser(data)) {
        unawaited(AppNotificationService.instance.handlePush(data));
      }
      return;
    }
    // iOS ใช้ push เดิมผ่าน AppDelegate และตรวจบัญชีผ่าน _iosNotifications
    if (defaultTargetPlatform != TargetPlatform.android ||
        !_canPresentForegroundUpdate(data)) {
      return;
    }
    final notification = message.notification;
    final title = notification?.title ?? data['title']?.toString();
    final body = notification?.body ?? data['body']?.toString();
    if (title == null || body == null) return;
    unawaited(
      ChatNotificationService.instance.showForegroundUpdate(
        title: title,
        body: body,
        data: data,
      ),
    );
  }

  bool _canPresentForegroundUpdate(Map<String, dynamic> data) {
    final category = data['category'];
    final expiry = DateTime.tryParse('${data['expires_at']}');
    return (category == 'app' || category == 'rental') &&
        data['recipient_id'] != null &&
        _belongsToCurrentUser(data) &&
        (expiry == null || expiry.isAfter(DateTime.now()));
  }

  void _queueTap(Map<String, dynamic> data) {
    _pendingTap = Map<String, dynamic>.from(data);
    unawaited(flushPendingTap());
  }

  bool _belongsToCurrentUser(Map<String, dynamic> data) {
    if (!AuthSession.isAuthenticated || !SupabaseConfig.isInitialized) {
      return false;
    }
    final recipient = data['recipient_id']?.toString();
    return recipient == null ||
        recipient == SupabaseConfig.client.auth.currentUser?.id;
  }

  Future<void> syncUserToken(String userId) async {
    if (_unregistering != null) await _unregistering;
    if (kIsWeb || userId.isEmpty || !AuthSession.isAuthenticated) return;
    if (!SupabaseConfig.isInitialized ||
        SupabaseConfig.client.auth.currentUser?.id != userId) {
      return;
    }
    if (_userId != userId) {
      _generation++;
      _userId = userId;
      _registeredUser = null;
      _registeredToken = null;
      _retryCount = 0;
    }
    final generation = _generation;
    // เรียงคำขอป้องกัน token เก่าที่ตอบช้าทับ token ใหม่หรือบัญชีที่สลับแล้ว
    _registrationQueue = _registrationQueue.then((_) async {
      if (generation != _generation || _userId != userId) return;
      try {
        await initialize();
        final fetched = _cachedToken ?? await _messaging?.getToken();
        // Token refresh อาจมาถึงระหว่างรอ getToken จึงให้ค่าที่ refresh แล้วมีลำดับก่อน
        final token = _cachedToken ?? fetched;
        if (token == null || token.isEmpty) throw StateError('token_not_ready');
        _cachedToken = token;
        final accessToken = AuthSession.accessToken;
        if (generation != _generation || accessToken == null) return;
        if (_registeredUser != userId || _registeredToken != token) {
          final source = NotificationDeviceDataSource();
          try {
            await source.register(
              accessToken: accessToken,
              installationId: await _installationId(),
              token: token,
              platform: defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
            );
          } finally {
            source.close();
          }
          if (generation != _generation) return;
          _registeredUser = userId;
          _registeredToken = token;
        }
        _retry?.cancel();
        _retryCount = 0;
        await flushPendingTap();
      } catch (error) {
        if (generation == _generation) {
          debugPrint(
            'FCM: device registration incomplete '
            '(${_failureCode(error)}); retry scheduled',
          );
          _retry?.cancel();
          final seconds = min(60, 3 * (1 << min(_retryCount++, 5)));
          _retry = Timer(Duration(seconds: seconds), () {
            if (_userId == userId) unawaited(syncUserToken(userId));
          });
        }
      }
    });
    await _registrationQueue;
  }

  String _failureCode(Object error) {
    // เก็บเฉพาะชนิดปัญหา ห้ามพิมพ์ exception เต็มซึ่งอาจมี token หรือข้อมูลผู้ใช้
    if (error is NotificationDeviceException) {
      return 'device_api_http_${error.statusCode}';
    }
    if (error is FirebaseException) {
      final message = error.message ?? '';
      if (message.contains('API_KEY_INVALID') ||
          message.contains('BAD CONFIG')) {
        return 'firebase_invalid_config';
      }
      if (message.contains('FIS_AUTH_ERROR')) {
        return 'firebase_installations_auth';
      }
      return 'firebase_unavailable';
    }
    return 'token_or_network_unavailable';
  }

  Future<String> _installationId() => _installation ??= () async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('notification_installation_id');
    if (existing != null && existing.length >= 16) return existing;
    final random = Random.secure();
    final id = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString('notification_installation_id', id);
    return id;
  }();

  Future<void> unregisterCurrentDevice() => _unregistering ??=
      _unregisterCurrentDevice().whenComplete(() => _unregistering = null);

  Future<void> _unregisterCurrentDevice() async {
    final hadRegistration =
        _userId != null || _registeredUser != null || _cachedToken != null;
    _generation++;
    _retry?.cancel();
    _userId = null;
    _pendingTap = null;
    _registeredUser = null;
    _registeredToken = null;
    AppNotificationService.instance.setSession(null);
    final accessToken = AuthSession.accessToken;
    if (!kIsWeb && accessToken != null && hadRegistration) {
      final source = NotificationDeviceDataSource();
      try {
        // รอ register เดิมจบก่อนถอนเครื่อง ป้องกันการผูกกลับหลัง logout
        await _registrationQueue;
        await source.unregister(
          accessToken: accessToken,
          installationId: await _installationId(),
        );
      } catch (_) {
        debugPrint('FCM: unregister unavailable; invalidating device token');
      } finally {
        source.close();
      }
    }
    try {
      if (!kIsWeb && hadRegistration) await _messaging?.deleteToken();
    } catch (_) {}
    _cachedToken = null;
    await ChatNotificationService.instance.cancelAllNotifications();
    AppNotificationService.instance.setSession(null);
  }

  Future<void> flushPendingTap() async {
    final data = _pendingTap;
    final callback = _onNotificationOpened;
    if (data == null || callback == null || !AuthSession.isAuthenticated) {
      return;
    }
    if (!_belongsToCurrentUser(data)) {
      _pendingTap = null;
      return;
    }
    _pendingTap = null;
    await callback(data);
  }
}
