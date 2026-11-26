import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/chat_notification_service.dart';
import 'package:mocktail/mocktail.dart';

class _NotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
  });

  late _NotificationsPlugin plugin;
  late ChatNotificationService service;
  late DidReceiveNotificationResponseCallback tap;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    plugin = _NotificationsPlugin();
    service = ChatNotificationService(notificationsPlugin: plugin);
    when(
      () => plugin.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse: any(
          named: 'onDidReceiveNotificationResponse',
        ),
      ),
    ).thenAnswer((invocation) async {
      tap =
          invocation.namedArguments[#onDidReceiveNotificationResponse]
              as DidReceiveNotificationResponseCallback;
      return true;
    });
    when(
      () => plugin.getNotificationAppLaunchDetails(),
    ).thenAnswer((_) async => null);
    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Android uses the category channel and preserves each tap payload',
    () async {
      final shownIds = <dynamic>[];
      final opened = <Map<String, dynamic>>[];
      final chats = <String>[];
      service.onPushNotificationTapped = opened.add;
      service.onNotificationTapped = chats.add;

      for (final (category, channel) in [
        ('rental', 'yuemnoi_rental_updates_v1'),
        ('app', 'yuemnoi_app_updates_v1'),
      ]) {
        final data = {
          'notification_id': 'id-$category',
          'recipient_id': 'user-1',
          'category': category,
          if (category == 'rental') 'booking_id': '42',
        };
        await service.showForegroundUpdate(
          title: category,
          body: 'update',
          data: data,
        );
        final captured = verify(
          () => plugin.show(
            id: captureAny(named: 'id'),
            title: category,
            body: 'update',
            notificationDetails: captureAny(named: 'notificationDetails'),
            payload: captureAny(named: 'payload'),
          ),
        ).captured;
        shownIds.add(captured[0]);
        final details = captured[1] as NotificationDetails;
        expect(details.android?.channelId, channel);
        tap(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: captured[2] as String,
          ),
        );
        expect(opened.last, data);
      }
      expect(shownIds.toSet(), hasLength(2));
      tap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'conversation-1',
        ),
      );
      expect(chats, ['conversation-1']);
    },
  );

  test('foreground updates skip chat and expired push payloads', () async {
    for (final data in [
      {'notification_id': 'message', 'category': 'chat'},
      {
        'notification_id': 'old-update',
        'category': 'app',
        'expires_at': '2000-01-01T00:00:00Z',
      },
    ]) {
      await service.showForegroundUpdate(
        title: 'title',
        body: 'body',
        data: data,
      );
    }
    verifyZeroInteractions(plugin);
  });
}
