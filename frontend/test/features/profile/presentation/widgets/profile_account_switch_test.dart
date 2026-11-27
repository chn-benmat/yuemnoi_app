import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/cache/app_cache.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/features/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/features/profile/presentation/pages/profile/profile.dart';
import 'package:frontend/features/profile/presentation/widgets/profile/profile_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const avatarA = 'https://example.test/account-a.png';
  const avatarB = 'https://example.test/account-b.png';
  late Completer<Map<String, Object?>> responseA;
  late Completer<Map<String, Object?>> responseB;
  final requestedProfiles = <String>{};

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString:
          'SUPABASE_URL=https://example.supabase.co\n'
          'SUPABASE_PUBLISHABLE_KEY=test-key',
    );
    for (final name in [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    await http.runWithClient(SupabaseConfig.initialize, () {
      return MockClient((request) async {
        final filter = request.url.queryParameters['user_id'];
        if (request.url.path != '/rest/v1/profile_tb' || filter == null) {
          throw StateError('Unexpected profile request: ${request.url.path}');
        }
        requestedProfiles.add(filter);
        final row = switch (filter) {
          'eq.account-a' => await responseA.future,
          'eq.account-b' => await responseB.future,
          _ => throw StateError('Unexpected profile filter'),
        };
        return http.Response(
          jsonEncode([row]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
    });
  });

  tearDownAll(() => Supabase.instance.dispose());

  Future<Session> recoverSession(String userId, String name) async {
    final response = await SupabaseConfig.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'token-$userId',
        'refresh_token': 'refresh-$userId',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': {'display_name': name},
        },
      }),
    );
    return response.session!;
  }

  Map<String, Object?> profile(String userId, String avatar) => {
    'user_id': userId,
    'username': userId,
    'user_image_url': avatar,
  };

  testWidgets('profile clears the old avatar and ignores its late response', (
    tester,
  ) async {
    responseA = Completer<Map<String, Object?>>();
    responseB = Completer<Map<String, Object?>>();
    addTearDown(() {
      AuthSession.clear();
      if (!responseA.isCompleted)
        responseA.complete(profile('account-a', avatarA));
      if (!responseB.isCompleted)
        responseB.complete(profile('account-b', avatarB));
    });
    final firstSession = await recoverSession('account-a', 'Account A');
    AuthSession.saveAccessToken(firstSession.accessToken);
    AppCache.rememberSnapshot('profile', 'account', 'account-a', [
      profile('account-a', avatarA),
    ]);
    final auth = _AuthBloc();
    final authStates = StreamController<AuthState>();
    whenListen(auth, authStates.stream, initialState: const AuthInitial());
    addTearDown(authStates.close);
    addTearDown(auth.close);

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
      ),
    );
    await tester.pumpAndSettle();

    ProfileHeader header() => tester.widget(find.byType(ProfileHeader));

    expect(header().avatarUrl, avatarA);
    expect(requestedProfiles, contains('eq.account-a'));

    final secondSession = await recoverSession('account-b', 'Account B');
    await tester.pump();
    expect(header().avatarUrl, isNull);

    AuthSession.saveAccessToken(secondSession.accessToken);
    authStates.add(LoginSuccess(session: secondSession));
    await tester.pumpAndSettle();
    expect(header().displayName, 'Account B');
    expect(header().avatarUrl, isNull);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ProfileInitialAvatar && widget.name == 'Account B',
      ),
      findsOneWidget,
    );
    expect(requestedProfiles, contains('eq.account-b'));

    responseB.complete(profile('account-b', avatarB));
    await tester.pumpAndSettle();
    expect(header().avatarUrl, avatarB);

    responseA.complete(profile('account-a', avatarA));
    await tester.pumpAndSettle();
    expect(header().displayName, 'Account B');
    expect(header().avatarUrl, avatarB);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
