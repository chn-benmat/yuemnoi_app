import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/notification/domain/app_notification.dart';

class ChatNotificationService {
  ChatNotificationService({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    AudioPlayer? audioPlayer,
  }) : _injectedPlugin = notificationsPlugin,
       _injectedAudioPlayer = audioPlayer;

  static final ChatNotificationService instance = ChatNotificationService();

  final FlutterLocalNotificationsPlugin? _injectedPlugin;
  FlutterLocalNotificationsPlugin? _lazyPlugin;

  final AudioPlayer? _injectedAudioPlayer;
  AudioPlayer? _lazyAudioPlayer;

  bool _isInitialized = false;
  Future<void>? _initializing;

  String? _pendingTap;
  Map<String, dynamic>? _pendingPushTap;
  void Function(Map<String, dynamic>)? _onPushNotificationTapped;
  void Function(String conversationId)? _onNotificationTapped;

  set onPushNotificationTapped(void Function(Map<String, dynamic>)? callback) {
    _onPushNotificationTapped = callback;
    final pending = _pendingPushTap;
    if (pending != null && callback != null) {
      _pendingPushTap = null;
      callback(pending);
    }
  }

  set onNotificationTapped(void Function(String conversationId)? callback) {
    _onNotificationTapped = callback;
    final pendingTap = _pendingTap;
    if (callback != null && pendingTap != null) {
      _pendingTap = null;
      callback(pendingTap);
    }
  }

  FlutterLocalNotificationsPlugin get _notificationsPlugin =>
      _injectedPlugin ?? (_lazyPlugin ??= FlutterLocalNotificationsPlugin());

  AudioPlayer get _audioPlayer =>
      _injectedAudioPlayer ?? (_lazyAudioPlayer ??= AudioPlayer());

  Future<void> initialize() {
    if (kIsWeb || _isInitialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    try {
      const androidSettings = AndroidInitializationSettings('ic_notification');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );

      final androidPlatform = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlatform != null) {
        // สร้าง Channel ข้อความแชทระดับสูงสุด (Importance.max) เพื่อให้เด้งเป็น Heads-up Banner ด้านบนจอทับแอปอื่น
        final chatChannel = AndroidNotificationChannel(
          'yuemnoi_chat_messages_v3',
          'ข้อความแชท Yuemnoi',
          description: 'การแจ้งเตือนข้อความใหม่แบบ Pop-up ด้านบน',
          importance: Importance.max,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 250, 150, 250]),
          playSound: true,
          showBadge: true,
          sound: const RawResourceAndroidNotificationSound('message_tone'),
        );
        await androidPlatform.createNotificationChannel(chatChannel);
        for (final details in [_appUpdates, _rentalUpdates, _returnReminder]) {
          await androidPlatform.createNotificationChannel(
            AndroidNotificationChannel(
              details.channelId,
              details.channelName,
              importance: details.importance,
              enableVibration: details.enableVibration,
              vibrationPattern: details.vibrationPattern,
              sound: details.sound,
            ),
          );
        }
      }

      final launchDetails = await _notificationsPlugin
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final response = launchDetails?.notificationResponse;
        if (response != null) _handleNotificationTap(response);
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('Notification initialization warning: $e');
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('push:')) {
      try {
        final data = jsonDecode(payload.substring(5)) as Map<String, dynamic>;
        if (data['notification_id'] is! String ||
            data['recipient_id'] is! String) {
          return;
        }
        final pushCallback = _onPushNotificationTapped;
        if (pushCallback == null) {
          _pendingPushTap = data;
        } else {
          pushCallback(data);
        }
      } on FormatException {
        // ข้อมูลแจ้งเตือนรุ่นเก่าบางรายการไม่มีเส้นทางที่เปิดได้
      } on TypeError {
        // ข้าม payload ที่ OS ส่งกลับมาในรูปแบบอื่น
      }
      return;
    }
    final callback = _onNotificationTapped;
    if (callback == null) {
      _pendingTap = payload;
      return;
    }
    callback(payload);
  }

  /// เล่นเสียงแจ้งเตือนข้อความใหม่พร้อมสั่น
  Future<void> playMessageSound() async {
    try {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play(AssetSource('sounds/message_tone.wav'));
    } catch (_) {}
  }

  /// ยกเลิกการแจ้งเตือนทั้งหมด
  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancelAll();
    } catch (_) {}
  }

  final Map<String, List<String>> _conversationMessages = {};
  final Set<String> _processedMessageKeys = {};

  static const _appUpdates = AndroidNotificationDetails(
    'yuemnoi_app_updates_v1',
    'การแจ้งเตือน Yuemnoi',
    importance: Importance.high,
    priority: Priority.high,
    visibility: NotificationVisibility.private,
  );

  static const _rentalUpdates = AndroidNotificationDetails(
    'yuemnoi_rental_updates_v1',
    'การเช่าสินค้า',
    importance: Importance.high,
    priority: Priority.high,
    visibility: NotificationVisibility.private,
  );

  static final _returnReminder = AndroidNotificationDetails(
    'yuemnoi_return_reminders_v1',
    'เตือนเวลาคืนสินค้า',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.private,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
  );

  Future<void> showPushNotification(
    AppNotification notification,
    Map<String, dynamic> data,
  ) async {
    final eventKey = data['event_key']?.toString() ?? notification.id;
    if (notification.id.isEmpty || !_processedMessageKeys.add(eventKey)) return;
    if (_processedMessageKeys.length > 300) {
      _processedMessageKeys.remove(_processedMessageKeys.first);
    }
    await initialize();
    final isChat = data['category'] == 'chat';
    final android = notification.isReturnReminder
        ? _returnReminder
        : isChat
        ? const AndroidNotificationDetails(
            'yuemnoi_chat_messages_v3',
            'ข้อความแชท Yuemnoi',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.private,
            sound: RawResourceAndroidNotificationSound('message_tone'),
          )
        : data['category'] == 'rental'
        ? _rentalUpdates
        : _appUpdates;
    try {
      await _notificationsPlugin.show(
        id:
            (notification.type == 'chat_message'
                    ? notification.conversationId ?? notification.id
                    : notification.id)
                .hashCode,
        title: notification.title,
        body: notification.type == 'chat_message'
            ? _cleanNotificationBody(notification.body)
            : notification.body,
        notificationDetails: NotificationDetails(
          android: android,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            threadIdentifier: notification.conversationId,
          ),
        ),
        payload: 'push:${jsonEncode(data)}',
      );
    } catch (_) {
      _processedMessageKeys.remove(eventKey);
      debugPrint('แสดงการแจ้งเตือนของระบบไม่สำเร็จ');
    }
  }

  /// ล้างประวัติการแจ้งเตือนของห้องแชทนั้นๆ เมื่อผู้ใช้เปิดเข้าไปอ่าน
  Future<void> clearConversationNotifications(String conversationId) async {
    _conversationMessages.remove(conversationId);
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancel(id: conversationId.hashCode);
    } catch (_) {}
  }

  /// แสดงการแจ้งเตือนระดับระบบ (System Notification) แบบซ้อนข้อความ (Stacked / Grouped Notifications)
  String _cleanNotificationBody(String raw) {
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

  Future<void> showSystemNotification({
    int? id,
    required String title,
    required String body,
    String? payload,
    String? messageId,
  }) async {
    if (kIsWeb) return;
    if (!_isInitialized) {
      await initialize();
    }

    final cleanBody = _cleanNotificationBody(body);
    final convId = (payload != null && payload.isNotEmpty) ? payload : title;

    // 🛡️ ป้องกันการแจ้งเตือนซ้ำ (Deduplication): หากเป็นข้อความเดียวกันที่เพิ่งแจ้งเตือนไป ให้ข้ามทันที
    final dedupeKey = (messageId != null && messageId.isNotEmpty)
        ? '${convId}_$messageId'
        : '${convId}_${title}_$cleanBody';
    if (_processedMessageKeys.contains(dedupeKey)) {
      debugPrint('Duplicate notification ignored for key: $dedupeKey');
      return;
    }
    _processedMessageKeys.add(dedupeKey);
    if (_processedMessageKeys.length > 300) {
      _processedMessageKeys.remove(_processedMessageKeys.first);
    }

    try {
      // 📚 บันทึกข้อความที่ซ้อนกันสำหรับห้องแชทนี้ (Stacked Lines)
      final lines = _conversationMessages.putIfAbsent(convId, () => <String>[]);
      lines.add(cleanBody);
      if (lines.length > 10) {
        lines.removeAt(0);
      }

      // ใช้ InboxStyleInformation เพื่อแสดงข้อความที่ซ้อนกันเมื่อผู้ใช้ขยายแถบแจ้งเตือน
      final inboxStyle = InboxStyleInformation(
        lines,
        contentTitle: title,
        summaryText: lines.length > 1 ? '${lines.length} ข้อความ' : null,
      );

      final notifId = id ?? convId.hashCode;

      final androidDetails = AndroidNotificationDetails(
        'yuemnoi_chat_messages_v3',
        'ข้อความแชท Yuemnoi',
        channelDescription: 'การแจ้งเตือนข้อความใหม่แบบ Pop-up ด้านบน',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        showWhen: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 250, 150, 250]),
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('message_tone'),
        icon: '@mipmap/ic_launcher',
        groupKey: 'com.yuemnoi.app.CHAT_MESSAGES',
        setAsGroupSummary: false,
        groupAlertBehavior: GroupAlertBehavior.children,
        styleInformation: inboxStyle,
        number: lines.length,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'message_tone.wav',
        threadIdentifier: 'yuemnoi_chat_thread',
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        id: notifId,
        title: title,
        body: cleanBody,
        notificationDetails: details,
        payload: payload,
      );

      // สร้าง / อัปเดต Group Summary เพื่อให้ Android จัดกลุ่มซ้อนการแจ้งเตือนทั้งหมดไว้ด้วยกันอย่างเป็นระเบียบ
      final groupSummaryAndroidDetails = AndroidNotificationDetails(
        'yuemnoi_chat_messages_v3',
        'ข้อความแชท Yuemnoi',
        channelDescription: 'การแจ้งเตือนข้อความใหม่แบบ Pop-up ด้านบน',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        groupKey: 'com.yuemnoi.app.CHAT_MESSAGES',
        setAsGroupSummary: true,
        groupAlertBehavior: GroupAlertBehavior.children,
        icon: '@mipmap/ic_launcher',
      );

      await _notificationsPlugin.show(
        id: 0,
        title: 'Yuemnoi',
        body: 'ข้อความใหม่',
        notificationDetails: NotificationDetails(
          android: groupSummaryAndroidDetails,
          iOS: iosDetails,
        ),
      );
    } catch (e) {
      debugPrint('Show system notification error: $e');
    }
  }

  void dispose() {
    try {
      _lazyAudioPlayer?.dispose();
      _injectedAudioPlayer?.dispose();
    } catch (_) {}
  }
}
