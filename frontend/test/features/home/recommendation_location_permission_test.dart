import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/core/services/recommendation_location_service.dart';
import 'package:frontend/features/profile/presentation/pages/account/change_account_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
  final legacyLocationRequests = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString:
          'SUPABASE_URL=https://example.supabase.co\n'
          'SUPABASE_PUBLISHABLE_KEY=test-key\n'
          'APP_SECRET_KEY=test-app-key',
    );
    for (final name in [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    await http.runWithClient(SupabaseConfig.initialize, () {
      return MockClient((request) async {
        if (request.url.path != '/rest/v1/user_recommendation_locations') {
          throw StateError('Unexpected request: ${request.url.path}');
        }
        legacyLocationRequests.add(request.method);
        return http.Response('[]', 404, request: request);
      });
    });
    await SupabaseConfig.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'test-user',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthSession.saveAccessToken('test-token');
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(notificationChannel, (call) async {
      expect(call.method, 'requestNotificationsPermission');
      return true;
    });
    legacyLocationRequests.clear();
  });
  tearDown(() {
    AuthSession.clear();
    messenger.setMockMethodCallHandler(locationChannel, null);
    messenger.setMockMethodCallHandler(notificationChannel, null);
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final allowed in [true, false]) {
    testWidgets(
      'handles the OS location decision directly (allowed: $allowed)',
      (tester) async {
        var permission = LocationPermission.denied;
        final decision = Completer<void>();
        final calls = <String>[];
        messenger.setMockMethodCallHandler(locationChannel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'checkPermission':
              return permission.index;
            case 'requestPermission':
              await decision.future;
              if (allowed) permission = LocationPermission.whileInUse;
              return permission.index;
            case 'isLocationServiceEnabled':
              return true;
            case 'getCurrentPosition':
              return {
                'latitude': 13.7467785,
                'longitude': 100.5349540,
                'timestamp': DateTime(2026, 1, 1).millisecondsSinceEpoch,
                'accuracy': 8.0,
              };
            default:
              throw StateError('Unexpected location method: ${call.method}');
          }
        });

        await tester.pumpWidget(
          const YuemnoiApp(initialRoute: AppRoutes.termsOfService),
        );
        await tester.pumpAndSettle();

        expect(SupabaseConfig.client.auth.currentUser?.id, 'test-user');
        expect(legacyLocationRequests, isEmpty);
        expect(AppRoutes.navigatorKey.currentState?.canPop(), isFalse);
        expect(calls, ['checkPermission', 'requestPermission']);

        decision.complete();
        await tester.pumpAndSettle();

        if (allowed) {
          expect(calls, contains('getCurrentPosition'));
        } else {
          expect(calls, isNot(contains('getCurrentPosition')));
        }
        expect(legacyLocationRequests, isEmpty);
        expect(AppRoutes.navigatorKey.currentState?.canPop(), isFalse);
      },
    );
  }

  testWidgets('an existing device grant is used until revoked in settings', (
    tester,
  ) async {
    var permission = LocationPermission.whileInUse;
    SharedPreferences.setMockInitialValues({
      'startup_location_permission_requested_v1': true,
    });
    final calls = <String>[];
    messenger.setMockMethodCallHandler(locationChannel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'checkPermission' => permission.index,
        'isLocationServiceEnabled' => true,
        'getCurrentPosition' => {
          'latitude': 13.7467785,
          'longitude': 100.5349540,
          'timestamp': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          'accuracy': 8.0,
        },
        _ => throw StateError('Unexpected location method: ${call.method}'),
      };
    });

    await tester.pumpWidget(
      const YuemnoiApp(initialRoute: AppRoutes.termsOfService),
    );
    await tester.pumpAndSettle();

    expect(AppRoutes.navigatorKey.currentState?.canPop(), isFalse);
    expect(calls, contains('getCurrentPosition'));
    expect(calls, isNot(contains('requestPermission')));
    expect(legacyLocationRequests, isEmpty);
    expect(
      RecommendationLocationService.instance.position.value?.latitude,
      13.7467785,
    );

    permission = LocationPermission.deniedForever;
    calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SupabaseConfig.client.auth.stopAutoRefresh();
    await tester.pumpAndSettle();

    expect(calls, ['checkPermission']);
    expect(RecommendationLocationService.instance.position.value, isNull);
  });

  testWidgets('a GPS timeout leaves the app usable without a position', (
    tester,
  ) async {
    final waitingForFix = Completer<Object?>();
    messenger.setMockMethodCallHandler(locationChannel, (call) async {
      return switch (call.method) {
        'checkPermission' => LocationPermission.whileInUse.index,
        'isLocationServiceEnabled' => true,
        'getCurrentPosition' => waitingForFix.future,
        _ => throw StateError('Unexpected location method: ${call.method}'),
      };
    });

    await tester.pumpWidget(
      const YuemnoiApp(initialRoute: AppRoutes.termsOfService),
    );
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    final location = RecommendationLocationService.instance;
    expect(location.position.value, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('startup_location_permission_requested_v1'), isTrue);
    expect(AppRoutes.navigatorKey.currentState?.canPop(), isFalse);
    expect(legacyLocationRequests, isEmpty);
    waitingForFix.complete(null);
  });

  testWidgets(
    'account security does not query the retired saved location table',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChangeAccountScreen()));
      await tester.pumpAndSettle();
      expect(legacyLocationRequests, isEmpty);
      expect(find.text('ลบบัญชีผู้ใช้'), findsOneWidget);
      expect(find.text('ลบตำแหน่งเดิมออกจากบัญชี'), findsNothing);
    },
  );
}
