import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:frontend/core/cache/app_cache.dart';
import 'package:frontend/core/cache/cache_database.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_session_validator.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/auth/domain/repositories/auth_repository.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/features/auth/presentation/pages/login.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _SessionApi extends Mock implements ApiClient {}

class _AuthRepository extends Mock implements AuthRepository {}

Session _session(String provider) => Session.fromJson({
  'access_token': 'recovery-token',
  'refresh_token': 'refresh-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': 'pending-user',
    'aud': 'authenticated',
    'created_at': '2026-10-17T00:00:00Z',
    'app_metadata': {'provider': provider},
    'user_metadata': <String, Object>{},
  },
})!;

void main() {
  const bearer = {'Authorization': 'Bearer recovery-token'};
  late _SessionApi client;
  late AuthBloc bloc;
  late _AuthRepository repository;
  late bool restored;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthSession.clear();
    restored = false;
    client = _SessionApi();
    repository = _AuthRepository();
    when(() => repository.close()).thenReturn(null);
    when(() => client.close()).thenReturn(null);
    when(() => client.get('/api/auth/session', headers: bearer)).thenAnswer(
      (_) async => restored
          ? const ApiResponse(
              statusCode: 200,
              data: {'user_id': 'pending-user'},
            )
          : const ApiResponse(
              statusCode: 409,
              data: {
                'code': 'account_deletion_pending',
                'delete_after': '2026-12-27T05:00:00Z',
              },
            ),
    );
    when(
      () => client.post('/api/auth/account/restore', headers: bearer),
    ).thenAnswer((_) async {
      restored = true;
      return const ApiResponse(
        statusCode: 200,
        data: {'user_id': 'pending-user'},
      );
    });
  });

  tearDown(() async {
    AuthSession.clear();
  });

  testWidgets('startup login takes priority over the previous browser route', (
    tester,
  ) async {
    final platform = tester.binding.platformDispatcher;
    platform.defaultRouteNameTestValue = AppRoutes.home;
    addTearDown(platform.clearDefaultRouteNameTestValue);
    final router = AppRoutes.createRouter(initialLocation: AppRoutes.login);
    addTearDown(router.dispose);

    expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
  });

  Future<void> openLogin(WidgetTester tester) async {
    final cache = CacheDatabase(NativeDatabase.memory());
    AppCache.useDatabase(cache);
    addTearDown(cache.close);
    bloc = AuthBloc(
      authRepository: repository,
      sessionValidator: AppSessionValidator(client: client),
    );
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => bloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                },
                child: const Text('Guest home'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Guest home'));
    await tester.pumpAndSettle();
  }

  testWidgets('password sign-in restores only after explicit confirmation', (
    tester,
  ) async {
    await openLogin(tester);
    bloc.add(AuthAuthStateChanged(_session('email')));
    await tester.pumpAndSettle();

    expect(bloc.state, isA<LoginNeedsAccountRestore>());
    expect(find.text('กู้คืนบัญชี'), findsOneWidget);
    expect(AuthSession.isAuthenticated, isFalse);
    verifyNever(() => client.post(any(), headers: any(named: 'headers')));

    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();

    verifyInOrder([
      () => client.post('/api/auth/account/restore', headers: bearer),
      () => client.get('/api/auth/session', headers: bearer),
    ]);
    expect(AuthSession.isAuthenticated, isTrue);
    expect(find.text('Guest home'), findsOneWidget);
  });

  testWidgets('canceling Google account restoration leaves login open', (
    tester,
  ) async {
    await openLogin(tester);
    final candidate = _session('google');
    bloc.add(AuthAuthStateChanged(candidate));
    await tester.pumpAndSettle();
    bloc.add(AuthAuthStateChanged(candidate));
    await tester.pumpAndSettle();

    expect(bloc.state, isA<LoginNeedsAccountRestore>());
    expect(find.text('กู้คืนบัญชี'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(AuthSession.isAuthenticated, isFalse);
    verifyNever(() => client.post(any(), headers: any(named: 'headers')));
  });
}
