import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/app_session_validator.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/auth/domain/repositories/auth_repository.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSessionApi extends Mock implements ApiClient {}

void main() {
  late MockAuthRepository repository;
  late MockSessionApi client;

  setUp(() {
    AuthSession.clear();
    repository = MockAuthRepository();
    client = MockSessionApi();
    when(() => repository.close()).thenReturn(null);
    when(() => client.close()).thenReturn(null);
    when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async =>
          const ApiResponse(statusCode: 403, data: {'code': 'dashboard_only'}),
    );
  });
  tearDown(AuthSession.clear);

  for (final provider in ['email', 'google']) {
    blocTest<AuthBloc, AuthState>(
      'rejects $provider session before reporting login success',
      build: () => AuthBloc(
        authRepository: repository,
        sessionValidator: AppSessionValidator(client: client),
      ),
      act: (bloc) => bloc.add(
        AuthAuthStateChanged(
          Session.fromJson({
            'access_token': 'old-session-token',
            'refresh_token': 'refresh-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'dashboard-user',
              'aud': 'authenticated',
              'created_at': '2026-10-17T00:00:00Z',
              'app_metadata': {'provider': provider},
              'user_metadata': <String, Object>{},
            },
          })!,
        ),
      ),
      expect: () => [
        isA<LoginFailure>().having(
          (s) => s.message,
          'message',
          dashboardOnlyMessage,
        ),
      ],
      verify: (_) => expect(AuthSession.isAuthenticated, isFalse),
    );
  }
}
