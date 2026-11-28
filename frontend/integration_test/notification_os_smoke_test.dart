import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/chat_notification_service.dart';
import 'package:frontend/features/notification/domain/app_notification.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android posts a return reminder in the vibrating channel', (
    _,
  ) async {
    const id = 'test-return-reminder';
    const title = 'ทดสอบเตือนคืนสินค้า';
    const channelId = 'yuemnoi_return_reminders_v1';
    final service = ChatNotificationService.instance;
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;

    await service.initialize();
    expect(await android.areNotificationsEnabled(), isTrue);
    final channels = await android.getNotificationChannels();
    final channel = channels!.singleWhere((channel) => channel.id == channelId);
    expect(channel.enableVibration, isTrue);
    expect(channel.vibrationPattern, orderedEquals([0, 500, 250, 500]));

    try {
      await service.showPushNotification(
        const AppNotification(
          id: id,
          type: 'rental_due_30m',
          title: title,
          body: 'ทดสอบ Android',
        ),
        const {
          'category': 'rental',
          'notification_id': id,
          'recipient_id': 'test-user',
        },
      );
      final notifications = await plugin.getActiveNotifications();
      final reminder = notifications.singleWhere(
        (notification) => notification.id == id.hashCode,
      );
      expect(reminder.title, title);
      expect(reminder.channelId, channelId);
    } finally {
      await plugin.cancel(id: id.hashCode);
    }
  });

  testWidgets('Firebase issues an Android device token', (_) async {
    await Firebase.initializeApp();
    final token = await FirebaseMessaging.instance.getToken().timeout(
      const Duration(seconds: 30),
    );
    expect(token != null && token.isNotEmpty, isTrue);
  }, skip: !const bool.fromEnvironment('VERIFY_LIVE_FCM'));
}
