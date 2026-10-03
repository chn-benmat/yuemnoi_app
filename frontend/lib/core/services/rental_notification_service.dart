import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'chat_notification_service.dart';

/// บริการจัดการแจ้งเตือนสถานะการเช่าและเตือนเวลาส่งคืนอุปกรณ์ (Rental Time Tracking & Expiration Notification Service)
/// ทำหน้าที่:
/// 1. แจ้งเตือนเวลาเช่าคงเหลือ / แจ้งเตือนเมื่อเลยกำหนดส่งคืนผ่าน Push & System Notification
/// 2. ตั้งเวลาแจ้งเตือนล่วงหน้าอัตโนมัติ (Scheduled Reminders) เช่น 2 ชั่วโมง, 1 ชั่วโมง, 30 นาที และเมื่อถึงกำหนด
/// 3. ยกเลิกการแจ้งเตือนเมื่อผู้ใช้ส่งคืนอุปกรณ์สำเร็จ
class RentalNotificationService {
  RentalNotificationService({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    ChatNotificationService? chatNotificationService,
  })  : _injectedPlugin = notificationsPlugin,
        _chatNotificationService = chatNotificationService;

  static final RentalNotificationService instance = RentalNotificationService();

  final FlutterLocalNotificationsPlugin? _injectedPlugin;
  FlutterLocalNotificationsPlugin? _lazyPlugin;
  final ChatNotificationService? _chatNotificationService;

  ChatNotificationService get _chatService =>
      _chatNotificationService ?? ChatNotificationService.instance;

  bool _isInitialized = false;
  final Set<int> _scheduledBookings = {};

  FlutterLocalNotificationsPlugin get _notificationsPlugin =>
      _injectedPlugin ?? (_lazyPlugin ??= FlutterLocalNotificationsPlugin());

  /// กำหนดค่าเริ่มต้นระบบแจ้งเตือนและ Channel สำหรับเวลาเช่า
  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();

      final androidPlatform = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlatform != null) {
        // Channel พิเศษสำหรับการแจ้งเตือนกำหนดเวลาส่งคืนอุปกรณ์
        final rentalChannel = const AndroidNotificationChannel(
          'yuemnoi_rental_reminders_v1',
          'แจ้งเตือนเวลาเช่า Yuemnoi',
          description: 'การแจ้งเตือนกำหนดเวลาส่งคืนอุปกรณ์และระยะเวลาคงเหลือ',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('message_tone'),
        );
        await androidPlatform.createNotificationChannel(rentalChannel);
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('RentalNotificationService initialize warning: $e');
    }
  }

  /// แสดงการแจ้งเตือนสถานะเวลาเช่าปัจจุบันทันที (ทั้งกรณีเหลือเวลา หรือกรณีเลยกำหนดส่งคืน)
  Future<void> notifyRentalTimeStatus({
    required String itemTitle,
    required DateTime endDateTime,
    DateTime? startDateTime,
    int? bookingId,
    String? conversationId,
  }) async {
    if (kIsWeb) return;
    if (!_isInitialized) {
      await initialize();
    }

    final content = buildNotificationContent(
      itemTitle: itemTitle,
      endDateTime: endDateTime,
      now: DateTime.now(),
    );
    final String title = content.title;
    final String body = content.body;

    try {
      // เล่นเสียงแจ้งเตือนพร้อม haptic
      try {
        await _chatService.playMessageSound();
      } catch (_) {}

      final notifId = (bookingId != null && bookingId > 0)
          ? (bookingId * 100) + 1
          : (itemTitle.hashCode.abs() % 100000);

      const androidDetails = AndroidNotificationDetails(
        'yuemnoi_rental_reminders_v1',
        'แจ้งเตือนเวลาเช่า Yuemnoi',
        channelDescription:
            'การแจ้งเตือนกำหนดเวลาส่งคืนอุปกรณ์และระยะเวลาคงเหลือ',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('message_tone'),
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'message_tone.wav',
      );

      await _notificationsPlugin.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: conversationId ?? itemTitle,
      );
    } catch (e) {
      debugPrint('RentalNotificationService show notification error: $e');
    }
  }

  /// ตั้งเวลาแจ้งเตือนล่วงหน้าอัตโนมัติ (Scheduled Reminders)
  /// เช่น ก่อนครบกำหนด 2 ชม., 1 ชม., 30 นาที และเมื่อถึงกำหนด
  Future<void> scheduleRentalReminders({
    required String itemTitle,
    required DateTime endDateTime,
    required int bookingId,
    String? conversationId,
  }) async {
    if (kIsWeb) return;
    if (!_isInitialized) {
      await initialize();
    }

    final now = DateTime.now();
    // หากเวลาสิ้นสุดผ่านไปแล้ว ไม่ต้องส่งแจ้งเตือนซ้ำทุกครั้งที่เปิดเข้าดูแชท
    if (endDateTime.isBefore(now)) {
      return;
    }

    // ป้องกันการตั้งเวลาซ้ำซ้อนสำหรับคำขอเช่าเดิม
    if (_scheduledBookings.contains(bookingId)) {
      return;
    }
    _scheduledBookings.add(bookingId);

    final formattedDue = formatDueDate(endDateTime);

    final reminderOffsets = [
      const Duration(hours: 2),
      const Duration(hours: 1),
      const Duration(minutes: 30),
      Duration.zero,
    ];

    for (int i = 0; i < reminderOffsets.length; i++) {
      final offset = reminderOffsets[i];
      final scheduledTime = endDateTime.subtract(offset);

      if (scheduledTime.isAfter(now)) {
        final notifId = (bookingId * 100) + 10 + i;
        final String title;
        final String body;

        if (offset == Duration.zero) {
          title = '⚠️ ครบกำหนดเวลาส่งคืน: $itemTitle';
          body =
              'ถึงกำหนดเวลาส่งคืนแล้ว (ครบกำหนดเมื่อ $formattedDue) กรุณานำอุปกรณ์ไปส่งคืน';
        } else if (offset.inHours >= 1) {
          title = '⏰ ใกล้ครบกำหนดส่งคืน: $itemTitle';
          body =
              'เหลือเวลาอีก ${offset.inHours} ชั่วโมง (ครบกำหนดเมื่อ $formattedDue) กรุณาเตรียมส่งคืนอุปกรณ์';
        } else {
          title = '⏰ ใกล้ครบกำหนดส่งคืน: $itemTitle';
          body =
              'เหลือเวลาอีก ${offset.inMinutes} นาที (ครบกำหนดเมื่อ $formattedDue) กรุณาเตรียมส่งคืนอุปกรณ์';
        }

        try {
          final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);
          const androidDetails = AndroidNotificationDetails(
            'yuemnoi_rental_reminders_v1',
            'แจ้งเตือนเวลาเช่า Yuemnoi',
            channelDescription:
                'การแจ้งเตือนกำหนดเวลาส่งคืนอุปกรณ์และระยะเวลาคงเหลือ',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            showWhen: true,
            enableVibration: true,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('message_tone'),
            icon: '@mipmap/ic_launcher',
          );

          await _notificationsPlugin.zonedSchedule(
            id: notifId,
            title: title,
            body: body,
            scheduledDate: tzScheduledTime,
            notificationDetails: const NotificationDetails(
              android: androidDetails,
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
                sound: 'message_tone.wav',
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: conversationId ?? itemTitle,
          );
        } catch (e) {
          debugPrint('Schedule reminder error for id $notifId: $e');
        }
      }
    }
  }

  /// ยกเลิกการแจ้งเตือนทั้งหมดของคำขอเช่านี้เมื่อส่งคืนเรียบร้อยแล้ว
  Future<void> cancelRentalReminders(int bookingId) async {
    if (kIsWeb) return;
    try {
      // ยกเลิกทั้งการแจ้งเตือนสดและการแจ้งเตือนที่ตั้งเวลาไว้
      _scheduledBookings.remove(bookingId);
      await _notificationsPlugin.cancel(id: (bookingId * 100) + 1);
      for (int i = 0; i < 5; i++) {
        await _notificationsPlugin.cancel(id: (bookingId * 100) + 10 + i);
      }
    } catch (e) {
      debugPrint('Cancel rental reminders error: $e');
    }
  }

  /// คำนวณหัวข้อและข้อความแจ้งเตือนตามระยะเวลาที่เหลือหรือเลยกำหนด
  static ({String title, String body, bool isOverdue, String durationText})
      buildNotificationContent({
    required String itemTitle,
    required DateTime endDateTime,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final bool isOverdue = currentTime.isAfter(endDateTime);
    final Duration diff = isOverdue
        ? currentTime.difference(endDateTime)
        : endDateTime.difference(currentTime);

    final durationText = formatDuration(diff, isOverdue: isOverdue);
    final formattedDue = formatDueDate(endDateTime);

    final String title;
    final String body;

    if (isOverdue) {
      title = '🚨 แจ้งเตือนเลยกำหนดส่งคืน: $itemTitle';
      body =
          'เลยกำหนดส่งคืนมาแล้ว $durationText (ครบกำหนดเมื่อ $formattedDue) กรุณาดำเนินการส่งคืนอุปกรณ์';
    } else {
      title = '🔔 แจ้งเตือนเวลาเช่า: $itemTitle';
      body =
          'เหลือเวลาอีก $durationText (ครบกำหนดเมื่อ $formattedDue) กรุณาเตรียมส่งคืนอุปกรณ์ตามเวลา';
    }

    return (
      title: title,
      body: body,
      isOverdue: isOverdue,
      durationText: durationText,
    );
  }

  /// แปลง Duration เป็นข้อความ เช่น "2 วัน 3 ชม. 15 นาที" หรือ "45 นาที"
  static String formatDuration(Duration diff, {required bool isOverdue}) {
    final days = diff.inDays;
    final hours = isOverdue ? diff.inHours : (diff.inHours % 24);
    final minutes = diff.inMinutes % 60;

    if (days > 0 && !isOverdue) {
      return '$days วัน $hours ชม. $minutes นาที';
    } else if (hours > 0) {
      return '$hours ชม. $minutes นาที';
    } else {
      return '$minutes นาที';
    }
  }

  /// แปลงวันที่ครบกำหนดส่งคืนเป็นรูปแบบภาษาไทย
  static String formatDueDate(DateTime dt) {
    try {
      return DateFormat('d MMM yyyy • HH:mm น.', 'th').format(dt);
    } catch (_) {
      final hourStr = dt.hour.toString().padLeft(2, '0');
      final minStr = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month}/${dt.year} • $hourStr:$minStr น.';
    }
  }
}
