import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_history_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const supabaseUrl = 'https://example.supabase.co';
  const itemImageUrl = 'https://example.test/camera.png';
  const lenderAvatarUrl = 'https://example.test/lender.png';
  const renterBookings = <Map<String, Object?>>[
    {'id': 25, 'user_id': 'renter', 'item_id': 7, 'status': 'completed'},
  ];
  Future<List<Map<String, Object?>>> Function(String?)? loadBookings;

  Future<void> recoverSession(String userId) async {
    await SupabaseConfig.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': userId,
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  }

  setUpAll(() async {
    for (final name in [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString: 'SUPABASE_URL=$supabaseUrl\nSUPABASE_PUBLISHABLE_KEY=test-key',
    );
    await SupabaseConfig.initialize();
    await Supabase.instance.dispose();
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        final rows = switch (request.url.pathSegments.last) {
          'booking_tb' =>
            await loadBookings?.call(request.url.queryParameters['user_id']) ??
                renterBookings,
          'item_tb' => [
            {
              'id': 7,
              'item_name': 'Test camera',
              'category': 'camera',
              'user_id': 'lender',
              'item_image_url': [itemImageUrl],
            },
          ],
          'public_profile_v'
              when request.url.queryParameters['user_id'] == 'eq.lender' =>
            {
              'display_name': 'Test lender',
              'user_image_url': lenderAvatarUrl,
              'is_verified': false,
            },
          'public_profile_v' => [
            {'user_id': 'lender', 'display_name': 'Test lender'},
          ],
          'review_tb' => [],
          _ => throw StateError('Unexpected request: ${request.url.path}'),
        };
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await recoverSession('renter');
  });

  tearDown(() => loadBookings = null);
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'review from rental history shows the product and lender photos',
    (tester) async {
      final router = AppRoutes.createRouter(
        initialLocation: AppRoutes.rentalHistory,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final productPhoto = find.image(const NetworkImage(itemImageUrl));
      expect(productPhoto, findsOneWidget);

      await tester.tap(find.text('ให้คะแนน'));
      await tester.pumpAndSettle();

      expect(find.text('รีวิว'), findsOneWidget);
      expect(productPhoto, findsOneWidget);
      expect(find.image(const NetworkImage(lenderAvatarUrl)), findsOneWidget);
      expect(find.textContaining('ของคุณเป็นอย่างไร'), findsNothing);
      expect(find.text('ให้คะแนนผู้ปล่อยเช่า'), findsOneWidget);

      final pendingHistory = Completer<List<Map<String, Object?>>>();
      loadBookings = (_) => pendingHistory.future;
      router.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('รีวิว'), findsNothing);
      expect(
        find.widgetWithText(RentalHistoryCard, 'Test camera'),
        findsOneWidget,
      );
      expect(find.byType(RentalHistoryLoadingSkeleton), findsNothing);

      pendingHistory.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีประวัติการเช่า'), findsOneWidget);
    },
  );

  testWidgets('a failed refresh keeps rental history visible and can retry', (
    tester,
  ) async {
    final router = AppRoutes.createRouter(
      initialLocation: AppRoutes.rentalHistory,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final camera = find.text('Test camera');
    expect(camera, findsOneWidget);

    final pendingRefresh = Completer<List<Map<String, Object?>>>();
    var requestStarted = false;
    loadBookings = (_) {
      requestStarted = true;
      return pendingRefresh.future;
    };
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(requestStarted, isTrue);
    expect(camera, findsOneWidget);
    expect(find.byType(RentalHistoryLoadingSkeleton), findsNothing);

    pendingRefresh.completeError(StateError('Temporary failure'));
    await tester.pumpAndSettle();

    expect(camera, findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);

    loadBookings = (_) async => [];
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();

    expect(camera, findsNothing);
    expect(find.text('ยังไม่มีประวัติการเช่า'), findsOneWidget);
  });

  testWidgets('rental history discards a previous account refresh', (
    tester,
  ) async {
    final router = AppRoutes.createRouter(
      initialLocation: AppRoutes.rentalHistory,
    );
    addTearDown(router.dispose);
    addTearDown(() => recoverSession('renter'));
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final camera = find.text('Test camera');
    expect(camera, findsOneWidget);

    final pendingRefresh = Completer<List<Map<String, Object?>>>();
    final nextAccount = Completer<List<Map<String, Object?>>>();
    loadBookings = (userFilter) => switch (userFilter) {
      'eq.renter' => pendingRefresh.future,
      'eq.new-renter' => nextAccount.future,
      _ => throw StateError('Unexpected user filter: $userFilter'),
    };
    final refresh = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(refresh.show());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    await recoverSession('new-renter');
    await tester.pump();
    expect(camera, findsNothing);
    expect(find.byType(RentalHistoryLoadingSkeleton), findsOneWidget);

    nextAccount.complete([]);
    await tester.pump();
    await tester.pump();
    expect(find.text('ยังไม่มีประวัติการเช่า'), findsOneWidget);

    pendingRefresh.complete(renterBookings);
    await tester.pumpAndSettle();
    expect(camera, findsNothing);
    expect(find.text('ยังไม่มีประวัติการเช่า'), findsOneWidget);
  });
}
