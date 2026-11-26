import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/services/app_notification_service.dart';
import 'package:frontend/features/notification/data/datasources/notification_remote_data_source.dart';
import 'package:frontend/features/notification/data/repositories/notification_repository_impl.dart';
import 'package:frontend/features/notification/presentation/widgets/global_app_notification_listener.dart';
import 'package:mocktail/mocktail.dart';

class _ApiClient extends Mock implements ApiClient {}

class _NotificationApi {
  _NotificationApi() {
    when(
      () => client.get(
        '/api/notifications',
        headers: any(named: 'headers'),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async {
      requests++;
      return ApiResponse(
        statusCode: 200,
        data: {
          'items': items,
          'unread_count': items.length,
          'server_time': _time.add(Duration(seconds: second)).toIso8601String(),
        },
      );
    });
    service = AppNotificationService(
      repository: NotificationRepositoryImpl(
        category: AppNotificationCategory.chat,
        dataSource: NotificationRemoteDataSource(
          client: client,
          token: () => 'test-session',
        ),
      ),
    );
  }

  static final _time = DateTime.utc(2026, 10, 21);
  final client = _ApiClient();
  late final AppNotificationService service;
  var requests = 0;
  var second = 1;
  final items = <Map<String, dynamic>>[];

  void receive(String id, {String category = 'chat'}) {
    second += 2;
    final eventTime = _time
        .add(Duration(seconds: second - 1))
        .toIso8601String();
    items.add({
      'id': id,
      'category': category,
      'type': 'test_event',
      'title': id,
      'body': 'รายละเอียดแจ้งเตือน',
      'created_at': eventTime,
      'updated_at': eventTime,
      'unread_count': 1,
    });
  }
}

void main() {
  void syncTest(
    String description,
    Future<void> Function(WidgetTester, _NotificationApi) body,
  ) {
    testWidgets(description, (tester) async {
      final api = _NotificationApi();
      try {
        await body(tester, api);
      } finally {
        await tester.pumpWidget(const SizedBox());
        api.service.dispose();
        await tester.pump();
      }
    });
  }

  syncTest(
    'idle inbox waits a minute before fallback fetch and recovers a missed push',
    (tester, api) async {
      final events = <AppNotification>[];
      api.service.foregroundEvents.listen(events.add);
      api.service.setSession('alice');
      await tester.pump();
      expect(api.requests, 1);

      for (var tick = 0; tick < 11; tick++) {
        await tester.pump(const Duration(seconds: 5));
      }
      await tester.pump(const Duration(seconds: 4));
      expect(
        api.requests,
        1,
        reason: 'An unchanged inbox must not be fetched every five seconds',
      );

      api.receive('missed-push');
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests, 2);
      expect(api.service.inbox.value.unreadCount, 1);
      expect(events.map((item) => item.id), ['missed-push']);
    },
  );

  syncTest(
    'foreground chat push immediately refreshes the chat banner with sound',
    (tester, api) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var sounds = 0;
      api.service.setSession('alice');
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: GlobalAppNotificationListener(
            service: api.service,
            playSound: () async => sounds++,
            child: const Scaffold(),
          ),
        ),
      );

      api.receive('chat');
      await api.service.handlePush({'notification_id': 'chat'});
      expect(api.service.inbox.value.error, isNull);
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsOneWidget);
      expect(api.requests, 2);
      expect(sounds, 1);
      expect(api.service.inbox.value.unreadCount, 1);

      await api.service.handlePush({'notification_id': 'chat'});
      await tester.pump();
      expect(sounds, 1);
      expect(tester.takeException(), isNull);
    },
  );

  syncTest(
    'background pauses API calls and resume immediately restores inbox silently',
    (tester, api) async {
      final events = <AppNotification>[];
      api.service.foregroundEvents.listen(events.add);
      api.service.setSession('alice');
      await tester.pump();
      expect(api.requests, 1);

      api.service.setForeground(false);
      api.receive('background');
      await api.service.handlePush({'notification_id': 'background'});
      await tester.pump(const Duration(minutes: 2));
      expect(api.requests, 1);
      expect(events, isEmpty);

      api.service.setForeground(true);
      await tester.pump();
      expect(api.requests, 2);
      expect(api.service.inbox.value.items.single.id, 'background');
      expect(events, isEmpty);

      api.service.setSession(null);
      await tester.pump(const Duration(minutes: 2));
      await api.service.handlePush({'notification_id': 'background'});
      await tester.pump();
      expect(api.requests, 2);
      expect(api.service.inbox.value.items, isEmpty);
    },
  );
}
