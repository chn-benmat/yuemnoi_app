import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/cache/app_cache.dart';
import 'package:frontend/core/cache/cache_database.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_session_validator.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSessionApi extends Mock implements ApiClient {}

class MockStartupAuth extends Mock implements GoTrueClient {}

Session session({bool dashboardOnly = false, bool editableFlag = false}) =>
    Session.fromJson({
      'access_token':
          'header.'
          'eyJleHAiOjQxMDI0NDQ4MDB9.signature',
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
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSessionApi client;
  late AppSessionValidator validator;

  setUpAll(() {
    final cache = CacheDatabase(NativeDatabase.memory());
    AppCache.useDatabase(cache);
    addTearDown(cache.close);
  });

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
        headers: {'Authorization': 'Bearer ${session().accessToken}'},
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
    expect(AuthSession.accessToken, session().accessToken);
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
    'leaves a pending account signed out and reports its deadline',
    () async {
      respond(409, {
        'code': 'account_deletion_pending',
        'delete_after': '2026-12-27T05:00:00Z',
      });

      await expectLater(
        AuthSession.accept(session(), validator: validator),
        throwsA(
          isA<AccountDeletionPending>().having(
            (error) => error.deleteAfter,
            'deleteAfter',
            DateTime.utc(2026, 12, 27, 5),
          ),
        ),
      );
      expect(AuthSession.accessToken, isNull);
    },
  );

  for (final event in [
    AuthChangeEvent.initialSession,
    AuthChangeEvent.signedIn,
  ]) {
    test(
      'startup requests login for pending accounts from ${event.name}',
      () async {
        final auth = MockStartupAuth();
        final candidate = session();
        when(() => auth.currentSession).thenReturn(candidate);
        when(
          () => auth.onAuthStateChange,
        ).thenAnswer((_) => Stream.value(AuthState(event, candidate)));
        when(
          () => auth.signOut(scope: SignOutScope.local),
        ).thenAnswer((_) async {});
        respond(409, {
          'code': 'account_deletion_pending',
          'delete_after': '2026-12-27T05:00:00Z',
        });

        final result = await AuthSession.restore(
          auth: auth,
          validator: validator,
        );
        expect(result.state, AuthStartupState.loginRequired);
        expect(AuthSession.isAuthenticated, isFalse);
        if (event == AuthChangeEvent.initialSession) {
          verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
          expect(result.oauthRestoreSession, isNull);
        } else {
          verifyNever(() => auth.signOut(scope: SignOutScope.local));
          expect(result.oauthRestoreSession, candidate);
        }
      },
    );
  }

  test('rejects a session after the deletion deadline', () async {
    respond(410, {
      'code': 'account_deletion_expired',
      'error': 'บัญชีนี้ครบกำหนดลบแล้ว',
    });

    await expectLater(
      AuthSession.accept(session(), validator: validator),
      throwsA(
        isA<AppSessionException>()
            .having((error) => error.rejected, 'rejected', true)
            .having(
              (error) => error.message,
              'message',
              'บัญชีนี้ครบกำหนดลบแล้ว',
            ),
      ),
    );
    expect(AuthSession.accessToken, isNull);
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
