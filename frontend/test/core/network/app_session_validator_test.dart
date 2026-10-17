import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_session_validator.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSessionApi extends Mock implements ApiClient {}

Session session({bool dashboardOnly = false, bool editableFlag = false}) =>
    Session.fromJson({
      'access_token': 'test-access-token',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'test-user',
        'aud': 'authenticated',
        'created_at': '2026-10-17T00:00:00Z',
        'app_metadata': {'dashboard_only': dashboardOnly},
        'user_metadata': {'dashboard_only': editableFlag},
      },
    })!;

void main() {
  late MockSessionApi client;
  late AppSessionValidator validator;

  setUp(() {
    AuthSession.clear();
    client = MockSessionApi();
    when(() => client.close()).thenReturn(null);
    validator = AppSessionValidator(client: client);
  });
  tearDown(() {
    AuthSession.clear();
    validator.close();
  });

  void respond(int status, Map<String, Object> body) {
    when(
      () => client.get(
        '/api/auth/session',
        headers: {'Authorization': 'Bearer test-access-token'},
      ),
    ).thenAnswer((_) async => ApiResponse(statusCode: status, data: body));
  }

  test(
    'rejects dashboard-only session before publishing an app token',
    () async {
      await expectLater(
        AuthSession.accept(session(dashboardOnly: true), validator: validator),
        throwsA(
          isA<AppSessionException>().having(
            (e) => e.message,
            'message',
            dashboardOnlyMessage,
          ),
        ),
      );
      expect(AuthSession.isAuthenticated, isFalse);
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    },
  );

  test(
    'rejects old session when the current server restriction changed',
    () async {
      respond(403, {'code': 'dashboard_only'});
      await expectLater(
        AuthSession.accept(session(), validator: validator),
        throwsA(
          isA<AppSessionException>().having(
            (e) => e.rejected,
            'rejected',
            true,
          ),
        ),
      );
      expect(AuthSession.accessToken, isNull);
    },
  );

  test('allows a regular user and ignores editable user metadata', () async {
    respond(200, {'user_id': 'test-user'});
    await AuthSession.accept(session(editableFlag: true), validator: validator);
    expect(AuthSession.accessToken, 'test-access-token');
  });

  test('does not publish a session with a different verified user', () async {
    respond(200, {'user_id': 'different-user'});
    await expectLater(
      AuthSession.accept(session(), validator: validator),
      throwsA(isA<AppSessionException>()),
    );
    expect(AuthSession.isAuthenticated, isFalse);
  });

  test(
    'does not accept a session when the access check is unavailable',
    () async {
      respond(503, {'error': 'unavailable'});
      await expectLater(
        AuthSession.accept(session(), validator: validator),
        throwsA(
          isA<AppSessionException>().having(
            (e) => e.rejected,
            'rejected',
            false,
          ),
        ),
      );
      expect(AuthSession.isAuthenticated, isFalse);
    },
  );
}
