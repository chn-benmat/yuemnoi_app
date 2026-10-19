import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/notification/data/datasources/notification_remote_data_source.dart';
import 'package:frontend/features/notification/data/repositories/notification_repository_impl.dart';
import 'package:frontend/features/notification/domain/entities/app_notification.dart';
import 'package:mocktail/mocktail.dart';

class _ApiClient extends Mock implements ApiClient {}

void main() {
  late _ApiClient client;
  late NotificationRepositoryImpl repository;

  setUp(() {
    client = _ApiClient();
    repository = NotificationRepositoryImpl(
      dataSource: NotificationRemoteDataSource(
        client: client,
        token: () => 'verified-session',
      ),
    );
  });

  test(
    'fetches private inbox through Go with bearer and maps grouped counters',
    () async {
      when(
        () => client.get(
          '/api/notifications',
          queryParameters: {'limit': 20, 'offset': 40},
          headers: {'Authorization': 'Bearer verified-session'},
        ),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {
            'items': [
              {
                'id': 'notice',
                'category': 'chat',
                'type': 'chat_message',
                'title': 'สมชาย',
                'body': 'สวัสดี',
                'conversation_id': 'conversation',
                'booking_id': 42,
                'unread_count': 5,
                'created_at': '2026-10-19T09:00:00Z',
                'updated_at': '2026-10-19T09:00:01Z',
              },
            ],
            'unread_count': 1,
            'server_time': '2026-10-19T09:00:02Z',
          },
        ),
      );
      final page = await repository.getInbox(limit: 20, offset: 40);
      expect(page.items.single.category, AppNotificationCategory.chat);
      expect(page.items.single.unreadCount, 5);
      expect(page.items.single.bookingId, '42');
      expect(page.unreadCount, 1);
    },
  );

  test('does not consider non-2xx read request a successful save', () async {
    when(
      () => client.post(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async => const ApiResponse(statusCode: 500, data: {}));
    await expectLater(
      repository.markRead('notice'),
      throwsA(isA<NotificationFailure>()),
    );
  });

  test(
    'read mutation carries snapshot boundary so a concurrent message stays unread',
    () async {
      final through = DateTime.utc(2026, 10, 19, 9);
      when(
        () => client.post(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => const ApiResponse(statusCode: 200, data: {}));
      await repository.markRead('notice', readThrough: through);
      verify(
        () => client.post(
          '/api/notifications/notice/read',
          data: {'read_through': through.toIso8601String()},
          headers: {'Authorization': 'Bearer verified-session'},
        ),
      ).called(1);
    },
  );

  test(
    'missing app-authorized token never calls the private endpoint',
    () async {
      repository = NotificationRepositoryImpl(
        dataSource: NotificationRemoteDataSource(
          client: client,
          token: () => null,
        ),
      );
      await expectLater(
        repository.getInbox(),
        throwsA(isA<NotificationFailure>()),
      );
      verifyNever(
        () => client.get(
          any(),
          headers: any(named: 'headers'),
          queryParameters: any(named: 'queryParameters'),
        ),
      );
    },
  );
}
