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
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'delivers a cold-start local tap when the callback is attached',
    () async {
      when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
        (_) async => const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'conversation-1',
          ),
        ),
      );
      await service.initialize();

      final chats = <String>[];
      service.onNotificationTapped = chats.add;
      service.onNotificationTapped = chats.add;

      expect(chats, ['conversation-1']);
    },
  );

  test('routes local taps and ignores old push payloads', () async {
    final chats = <String>[];
    service.onNotificationTapped = chats.add;
    await service.initialize();

    for (final payload in [
      null,
      '',
      'push:{"category":"app"}',
      'conversation-1',
    ]) {
      tap(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: payload,
        ),
      );
    }

    expect(chats, ['conversation-1']);
  });
}
