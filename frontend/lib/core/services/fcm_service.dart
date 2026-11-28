import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/notification/data/notification_remote_data_source.dart';
import '../../features/notification/domain/app_notification.dart';
import '../network/auth_session.dart';
import '../network/notification_device_data_source.dart';
import 'chat_notification_service.dart';

class FcmService {
  FcmService._();

  static final instance = FcmService._();

  FirebaseMessaging? _messaging;
  Future<void>? _initializing;
  Future<String>? _installation;
  Future<void> _deviceQueue = Future.value();
  Future<void>? _unregistering;
  Timer? _retry;
  String? _registeredUser;
  String? _registeredToken;
  bool _signingOut = false;
  Map<String, dynamic>? _pendingTap;
  final _updates = StreamController<void>.broadcast();
  Stream<void> get updates => _updates.stream;
  bool Function(String)? isConversationVisible;
  void Function(AppNotification)? onOpened;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() {
    if (!_supported || _messaging != null) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      await ChatNotificationService.instance.initialize();
      ChatNotificationService.instance.onPushNotificationTapped = _open;
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(initial.data);
      FirebaseMessaging.onMessage.listen(_present);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _open(message.data),
      );
      messaging.onTokenRefresh.listen(
        (_) => unawaited(syncDevice()),
        onError: (Object _) {},
      );
      _messaging = messaging;
    } catch (_) {
      debugPrint('Firebase Messaging ยังไม่พร้อมใช้งาน');
    }
  }

  static bool canPresent({
    required AppNotification notification,
    required bool conversationVisible,
  }) => !conversationVisible || !notification.isConversationMessage;

  void _present(RemoteMessage message) {
    final data = message.data;
    if (!_belongsToCurrentUser(data)) return;
    _updates.add(null);
    final expiry = DateTime.tryParse('${data['expires_at']}');
    if (expiry != null && !expiry.isAfter(DateTime.now())) return;
    final notification = AppNotification.fromJson(data);
    final roomId = notification.conversationId;
    if (!canPresent(
      notification: notification,
      conversationVisible:
          roomId != null && (isConversationVisible?.call(roomId) ?? false),
    )) {
      return;
    }
    unawaited(
      ChatNotificationService.instance.showPushNotification(notification, data),
    );
  }

  bool _belongsToCurrentUser(Map<String, dynamic> data) {
    final currentUser = AuthSession.userId;
    return !_signingOut &&
        currentUser != null &&
        data['recipient_id'] == currentUser;
  }

  void _open(Map<String, dynamic> data) {
    _pendingTap = data;
    flushTap();
  }

  void flushTap() {
    final data = _pendingTap;
    final callback = onOpened;
    if (data == null || callback == null || AuthSession.userId == null) return;
    _pendingTap = null;
    if (!_belongsToCurrentUser(data)) return;
    final notification = AppNotification.fromJson(data);
    callback(notification);
    final token = AuthSession.accessToken;
    if (token != null && notification.id.isNotEmpty) {
      unawaited(_recordOpened(notification.id, token));
    }
  }

  Future<void> _recordOpened(String id, String token) async {
    final source = NotificationRemoteDataSource();
    try {
      await source.markRead(token, id);
      if (AuthSession.accessToken == token) _updates.add(null);
    } catch (_) {
      // แจ้งเตือนที่แตะยังเปิดรายละเอียดได้เมื่อประวัติอัปเดตไม่สำเร็จ
    } finally {
      source.close();
    }
  }

  Future<void> syncDevice({bool signedIn = false}) async {
    if (signedIn) _updates.add(null);
    final userId = AuthSession.userId;
    if (!_supported || userId == null || (_signingOut && !signedIn)) return;
    if (signedIn && _unregistering != null) {
      await _unregistering;
      if (AuthSession.userId != userId) return;
    }
    _signingOut = false;
    flushTap();
    return _deviceQueue = _deviceQueue.then((_) => _register(userId));
  }

  Future<void> _register(String userId) async {
    try {
      if (_signingOut || AuthSession.userId != userId) return;
      await initialize();
      final messaging = _messaging;
      if (_signingOut || AuthSession.userId != userId) return;
      if (messaging == null) throw StateError('fcm_not_ready');
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await messaging.getAPNSToken() == null) {
        throw StateError('apns_token_pending');
      }
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 8),
      );
      final accessToken = AuthSession.accessToken;
      if (_signingOut || AuthSession.userId != userId || accessToken == null) {
        return;
      }
      if (token == null) throw StateError('fcm_token_pending');
      if (userId == _registeredUser && token == _registeredToken) return;
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
      _registeredUser = userId;
      _registeredToken = token;
      _retry?.cancel();
    } catch (_) {
      if (_signingOut || AuthSession.userId != userId) return;
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 30), () {
        if (!_signingOut && AuthSession.userId == userId) {
          unawaited(syncDevice());
        }
      });
    }
  }

  Future<void> unregisterCurrentDevice() {
    if (!_supported || _signingOut) return _unregistering ?? Future.value();
    _signingOut = true;
    _retry?.cancel();
    _pendingTap = null;
    final accessToken = AuthSession.accessToken;
    final operation = _deviceQueue.then((_) async {
      _registeredUser = null;
      _registeredToken = null;
      if (accessToken != null) {
        final source = NotificationDeviceDataSource();
        try {
          await source.unregister(
            accessToken: accessToken,
            installationId: await _installationId(),
          );
        } catch (_) {
          // ลบ token ในเครื่องเมื่อ API ถอนการลงทะเบียนใช้ไม่ได้
        } finally {
          source.close();
        }
      }
      try {
        await _messaging?.deleteToken().timeout(const Duration(seconds: 5));
      } catch (_) {}
      await ChatNotificationService.instance.cancelAllNotifications();
    });
    _deviceQueue = operation;
    return _unregistering = operation.whenComplete(() => _unregistering = null);
  }

  Future<String> _installationId() => _installation ??= () async {
    final preferences = await SharedPreferences.getInstance();
    const key = 'notification_installation_id';
    final existing = preferences.getString(key);
    if (existing != null && existing.length >= 16) return existing;
    final random = Random.secure();
    final id = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await preferences.setString(key, id);
    return id;
  }();
}
