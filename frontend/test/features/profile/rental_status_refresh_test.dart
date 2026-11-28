import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_status_widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const supabaseUrl = 'https://example.supabase.co';
  late Completer<int> bookingsResponse;
  late bool bookingsAreEmpty;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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
      realtimeClientOptions: RealtimeClientOptions(
        transport: (_, _) => throw StateError('No WebSocket in this test'),
        disconnectOnEmptyChannelsAfter: Duration.zero,
      ),
      httpClient: MockClient((request) async {
        final query = request.url.queryParameters;
        final List<Map<String, Object>> rows;
        switch (request.url.pathSegments.last) {
          case 'booking_tb':
            if (query['user_id'] == 'eq.account-a') {
              final statusCode = await bookingsResponse.future;
              if (statusCode != 200) {
                return http.Response(
                  '{"message":"Could not load bookings"}',
                  statusCode,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
            }
            rows = bookingsAreEmpty
                ? []
                : [
                    if (query['user_id'] == 'eq.account-a')
                      {
                        'id': 21,
                        'user_id': 'account-a',
                        'item_id': 7,
                        'status': 'pending',
                      }
                    else if (query['item_id'] == 'in.(8)')
                      {
                        'id': 22,
                        'user_id': 'renter',
                        'item_id': 8,
                        'status': 'pending',
                      },
                  ];
          case 'item_tb':
            rows = switch (query['id']) {
              'in.(7)' => [
                {'id': 7, 'item_name': 'Rented camera', 'user_id': 'lender'},
              ],
              'in.(8)' => [
                {'id': 8, 'item_name': 'Lent tripod', 'user_id': 'account-a'},
              ],
              _ =>
                query['user_id'] == 'eq.account-a'
                    ? [
                        {'id': 8},
                      ]
                    : [],
            };
          case 'public_profile_v':
            rows = [
              {'user_id': 'lender', 'display_name': 'Test lender'},
              {'user_id': 'renter', 'display_name': 'Test renter'},
            ];
          default:
            throw StateError('Unexpected request: ${request.url.path}');
        }
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  Future<void> signInAs(String userId) async {
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

  setUp(() async {
    bookingsAreEmpty = false;
    await signInAs('account-a');
  });

  tearDownAll(() => Supabase.instance.dispose());

  Future<void> openRentalStatus(WidgetTester tester) async {
    final router = AppRoutes.createRouter(
      initialLocation: AppRoutes.rentalStatus,
    );
    addTearDown(router.dispose);
    bookingsResponse = Completer<int>();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  Future<void> refreshRentalStatus(WidgetTester tester) {
    bookingsResponse = Completer<int>();
    return tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
  }

  testWidgets('tapping a rental card does not open details on either tab', (
    tester,
  ) async {
    await openRentalStatus(tester);
    bookingsResponse.complete(200);
    await tester.pumpAndSettle();

    final details = find.text('รายละเอียดสถานะการเช่า');
    await tester.tap(find.text('Rented camera'));
    await tester.pumpAndSettle();
    expect(details, findsNothing);

    await tester.tap(find.text('ปล่อยเช่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lent tripod'));
    await tester.pumpAndSettle();
    expect(details, findsNothing);

    await tester.tap(find.text('ตรวจสอบคำขอเช่า'));
    await tester.pumpAndSettle();
    expect(details, findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps both rental lists and counts until refresh completes', (
    tester,
  ) async {
    await openRentalStatus(tester);
    final headerCounts = find.descendant(
      of: find.ancestor(
        of: find.text('สถานะการเช่า'),
        matching: find.byType(SafeArea),
      ),
      matching: find.text('1'),
    );

    expect(find.byType(RentalStatusLoadingSkeleton), findsOneWidget);
    bookingsResponse.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('Rented camera'), findsOneWidget);

    unawaited(refreshRentalStatus(tester));
    await tester.pump();

    expect(find.byType(RentalStatusLoadingSkeleton), findsNothing);
    expect(find.text('Rented camera'), findsOneWidget);
    expect(headerCounts, findsNWidgets(2));
    await tester.tap(find.text('ปล่อยเช่า'));
    await tester.pumpAndSettle();
    expect(find.text('Lent tripod'), findsOneWidget);

    bookingsAreEmpty = true;
    bookingsResponse.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีรายการปล่อยเช่า'), findsOneWidget);
    expect(find.text('Lent tripod'), findsNothing);
    expect(headerCounts, findsNothing);
    await tester.tap(find.text('เช่า'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีรายการเช่าอุปกรณ์'), findsOneWidget);
    expect(find.text('Rented camera'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a late refresh cannot restore bookings from a previous user', (
    tester,
  ) async {
    await openRentalStatus(tester);
    bookingsResponse.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('Rented camera'), findsOneWidget);

    unawaited(refreshRentalStatus(tester));
    await tester.pump();
    await signInAs('account-b');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Rented camera'), findsNothing);
    expect(find.text('ยังไม่มีรายการเช่าอุปกรณ์'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    bookingsResponse.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('Rented camera'), findsNothing);
    expect(find.text('ยังไม่มีรายการเช่าอุปกรณ์'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retry can refresh the last loaded rentals after an error', (
    tester,
  ) async {
    await openRentalStatus(tester);
    bookingsResponse.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('Rented camera'), findsOneWidget);

    unawaited(refreshRentalStatus(tester));
    bookingsResponse.complete(400);
    await tester.pumpAndSettle();
    expect(find.text('Rented camera'), findsOneWidget);
    expect(find.text('อัปเดตสถานะการเช่าไม่สำเร็จ'), findsOneWidget);

    bookingsResponse = Completer<int>();
    await tester.tap(find.text('ลองใหม่อีกครั้ง'));
    await tester.pump();
    expect(find.text('Rented camera'), findsOneWidget);
    expect(find.byType(RentalStatusLoadingSkeleton), findsNothing);

    bookingsResponse.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('Rented camera'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
