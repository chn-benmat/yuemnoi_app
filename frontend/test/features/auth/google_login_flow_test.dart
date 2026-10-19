import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:frontend/features/auth/data/datasources/google_auth_data_source.dart';
import 'package:frontend/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/features/auth/presentation/pages/login.dart';
import 'package:frontend/features/auth/presentation/widgets/social_button.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _MockApiClient extends Mock implements ApiClient {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleAccount extends Mock implements GoogleSignInAccount {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final browserLaunches = <MethodCall>[];
  late _MockGoogleSignIn google;
  late _MockGoogleAccount account;
  late _MockGoTrueClient auth;
  late GoogleAuthDataSource dataSource;

  void loadConfig({
    String clientId = 'test-web-client.apps.googleusercontent.com',
  }) {
    dotenv.loadFromString(
      envString:
          '''
SUPABASE_URL=https://example.supabase.co
SUPABASE_PUBLISHABLE_KEY=test-publishable-key
APP_SECRET_KEY=test-client-key
GOOGLE_WEB_CLIENT_ID=$clientId
''',
    );
  }

  AuthBloc createBloc() {
    final bloc = AuthBloc(
      authRepository: AuthRepositoryImpl(
        AuthRemoteDataSource(client: _MockApiClient()),
        googleAuthDataSource: dataSource,
      ),
    );
    addTearDown(bloc.close);
    return bloc;
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    loadConfig();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') browserLaunches.add(call);
            return true;
          },
        );
    await SupabaseConfig.initialize();
  });

  setUp(() {
    loadConfig();
    browserLaunches.clear();
    google = _MockGoogleSignIn();
    account = _MockGoogleAccount();
    auth = _MockGoTrueClient();
    dataSource = GoogleAuthDataSource(auth: auth, googleSignIn: google);
    when(
      () => google.initialize(serverClientId: any(named: 'serverClientId')),
    ).thenAnswer((_) async {});
    when(() => google.signOut()).thenAnswer((_) async {});
    when(() => account.authentication).thenReturn(
      const GoogleSignInAuthentication(idToken: 'test-google-id-token'),
    );
    when(() => google.authenticate()).thenAnswer((_) async => account);
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: any(named: 'idToken'),
      ),
    ).thenAnswer(
      (_) async => AuthResponse(
        session: Session.fromJson({
          'access_token': 'test-session-token',
          'refresh_token': 'test-refresh-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'test-user',
            'aud': 'authenticated',
            'created_at': '2026-10-19T00:00:00Z',
            'app_metadata': {'provider': 'google'},
            'user_metadata': <String, Object>{},
          },
        }),
      ),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    dotenv.clean();
  });

  test('Android Google login does not launch an external browser', () async {
    final picker = Completer<GoogleSignInAccount>();
    when(() => google.authenticate()).thenAnswer((_) => picker.future);
    final bloc = createBloc();
    bloc.add(const AuthGoogleLoginRequested());
    await pumpEventQueue();

    expect(bloc.state, isA<GoogleLoginLoading>());
    expect(
      browserLaunches,
      isEmpty,
      reason: 'Google login must open the native account picker on Android.',
    );
    verify(() => google.authenticate()).called(1);
    picker.completeError(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await pumpEventQueue();
    expect(bloc.state, isA<AuthInitial>());
  });

  test('exchanges the native ID token for a Supabase session', () async {
    expect(await dataSource.login(), isTrue);
    verifyInOrder([
      () => google.initialize(
        serverClientId: 'test-web-client.apps.googleusercontent.com',
      ),
      () => google.signOut(),
      () => google.authenticate(),
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'test-google-id-token',
      ),
    ]);
    expect(browserLaunches, isEmpty);
  });

  test(
    'initializes once and requests account selection on every login',
    () async {
      await dataSource.login();
      await dataSource.login();
      verify(
        () => google.initialize(serverClientId: any(named: 'serverClientId')),
      ).called(1);
      verify(() => google.signOut()).called(2);
      verify(() => google.authenticate()).called(2);
    },
  );

  test('cancellation returns to idle and allows another login', () async {
    when(() => google.authenticate()).thenThrow(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    final bloc = createBloc();
    final states = <AuthState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);
    bloc.add(const AuthGoogleLoginRequested());
    await pumpEventQueue();
    bloc.add(const AuthGoogleLoginRequested());
    await pumpEventQueue();
    expect(states, [
      isA<GoogleLoginLoading>(),
      isA<AuthInitial>(),
      isA<GoogleLoginLoading>(),
      isA<AuthInitial>(),
    ]);
    verifyNever(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: any(named: 'idToken'),
      ),
    );
    expect(browserLaunches, isEmpty);
  });

  test('repeated taps cannot open concurrent account pickers', () async {
    final picker = Completer<GoogleSignInAccount>();
    when(() => google.authenticate()).thenAnswer((_) => picker.future);
    final bloc = createBloc();
    bloc.add(const AuthGoogleLoginRequested());
    bloc.add(const AuthGoogleLoginRequested());
    await pumpEventQueue();
    verify(() => google.authenticate()).called(1);
    picker.complete(account);
    await pumpEventQueue();
  });

  test(
    'missing client ID reports configuration failure without a browser',
    () async {
      loadConfig(clientId: '');
      final bloc = createBloc();
      bloc.add(const AuthGoogleLoginRequested());
      await pumpEventQueue();
      expect(
        bloc.state,
        isA<LoginFailure>().having(
          (state) => state.message,
          'message',
          contains('GOOGLE_WEB_CLIENT_ID'),
        ),
      );
      verifyNever(() => google.authenticate());
      expect(browserLaunches, isEmpty);
    },
  );

  test('missing ID token never creates a Supabase session', () async {
    when(
      () => account.authentication,
    ).thenReturn(const GoogleSignInAuthentication(idToken: null));
    await expectLater(dataSource.login(), throwsA(isA<AuthException>()));
    verifyNever(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: any(named: 'idToken'),
      ),
    );
    expect(browserLaunches, isEmpty);
  });

  test(
    'native configuration failure does not fall back to a browser',
    () async {
      when(() => google.authenticate()).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      );
      final bloc = createBloc();
      bloc.add(const AuthGoogleLoginRequested());
      await pumpEventQueue();
      expect(
        bloc.state,
        isA<LoginFailure>().having(
          (state) => state.message,
          'message',
          contains('SHA-1'),
        ),
      );
      expect(browserLaunches, isEmpty);
    },
  );

  test('iOS retains its existing OAuth redirect flow', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final oauth = GoogleAuthDataSource(
      auth: SupabaseConfig.client.auth,
      googleSignIn: google,
    );
    expect(await oauth.login(), isTrue);
    expect(browserLaunches, hasLength(1));
    final arguments = browserLaunches.single.arguments as Map;
    final url = Uri.parse(arguments['url'] as String);
    expect(url.queryParameters['prompt'], 'select_account');
    expect(url.queryParameters['redirect_to'], SupabaseConfig.oauthRedirectUrl);
    verifyNever(() => google.authenticate());
  });

  testWidgets('cancelling the picker enables the Google button again', (
    tester,
  ) async {
    final picker = Completer<GoogleSignInAccount>();
    when(() => google.authenticate()).thenAnswer((_) => picker.future);
    final bloc = createBloc();
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byType(SocialButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(bloc.state, isA<GoogleLoginLoading>());
    picker.completeError(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await tester.pumpAndSettle();
    expect(bloc.state, isA<AuthInitial>());
    expect(find.byType(SnackBar), findsNothing);
    when(() => google.authenticate()).thenThrow(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    verify(() => google.authenticate()).called(2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
