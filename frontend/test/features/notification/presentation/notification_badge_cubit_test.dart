import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_session_validator.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/notification/data/notification_remote_data_source.dart';
import 'package:frontend/features/notification/presentation/bloc/notification_badge_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Api extends Mock implements ApiClient {}

const _headers = {'Authorization': 'Bearer badge-token'};

void main() {
  late _Api api;
  late Map<String, Object> latest;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = _Api();
    latest = _item('2026-11-29T10:00:00Z', read: false);
    when(() => api.get('/api/auth/session', headers: _headers)).thenAnswer(
      (_) async =>
          const ApiResponse(statusCode: 200, data: {'user_id': 'badge-user'}),
    );
    when(
      () => api.get(
        '/api/notifications',
        headers: _headers,
        queryParameters: {'limit': 1, 'offset': 0},
      ),
    ).thenAnswer(
      (_) async => ApiResponse(
        statusCode: 200,
        data: {
          'items': [latest],
        },
      ),
    );
    await AuthSession.accept(
      Session(
        accessToken: 'badge-token',
        tokenType: 'bearer',
        user: const User(
          id: 'badge-user',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-10-17T00:00:00Z',
        ),
      ),
      validator: AppSessionValidator(client: api),
    );
  });

  tearDown(AuthSession.clear);

  NotificationBadgeCubit build() =>
      NotificationBadgeCubit(source: NotificationRemoteDataSource(client: api));

  test(
    'shows the dot for an unread notification before the tab is opened',
    () async {
      final cubit = build();
      await cubit.check();
      expect(cubit.state, isTrue);
    },
  );

  test(
    'opening the tab hides the dot until a newer notification arrives',
    () async {
      final cubit = build();
      await cubit.check();
      await cubit.markSeen();
      expect(cubit.state, isFalse);

      // อ่านหรือไม่อ่านไม่สำคัญ ตรวจซ้ำด้วยรายการเดิมต้องไม่ขึ้นจุด
      await cubit.check();
      expect(cubit.state, isFalse);

      latest = _item('2026-11-29T10:05:00Z', read: false);
      await cubit.check();
      expect(cubit.state, isTrue);
    },
  );

  test('no dot for a guest', () async {
    AuthSession.clear();
    final cubit = build();
    await cubit.check();
    expect(cubit.state, isFalse);
  });
}

Map<String, Object> _item(String updatedAt, {required bool read}) => {
  'id': updatedAt,
  'type': 'chat_message',
  'title': 'แจ้งเตือน',
  'body': 'ข้อความใหม่',
  'updated_at': updatedAt,
  'is_read': read,
};
