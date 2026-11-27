import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/core/network/supabase_client.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/booking_request_bubble_card.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_tracking_map_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final localDeadline = DateTime(2099, 11, 27, 17);
  Completer<Map<String, Object>>? bookingResponse;

  setUpAll(() async {
    await initializeDateFormatting('th');
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
        if (request.url.path != '/rest/v1/booking_tb' ||
            request.url.queryParameters['id'] != 'eq.36') {
          throw StateError('Unexpected booking request: ${request.url}');
        }
        final booking = await bookingResponse?.future;
        return http.Response(
          jsonEncode([
            booking ??
                {
                  'id': 36,
                  'status': 'active',
                  'end_at': localDeadline.toUtc().toIso8601String(),
                },
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
    });
    await SupabaseConfig.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'renter',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  const legacyMessageId = 'legacy-booking-message';

  Future<void> pumpCard(
    WidgetTester tester, {
    String? status,
    bool legacy = false,
    VoidCallback? onRetryCustomerRequest,
  }) async {
    final bookingData = BookingRequestData(
      item: const BookingItemInfo(
        id: 1,
        title: 'Camera',
        imageUrl: '',
        rating: 4.8,
        reviewCount: 1,
        hourlyRate: 150,
        dailyRate: 700,
        defaultLocation: 'Pickup point',
      ),
      startDate: DateTime(2099, 11, 26),
      endDate: DateTime(2099, 11, 27),
      startTime: const TimeOfDay(hour: 15, minute: 0),
      endTime: const TimeOfDay(hour: 15, minute: 0),
      location: 'Pickup point',
      bookingId: legacy ? null : 36,
      status: status,
      isCustomerRequest: !legacy,
    );
    final message = ChatMessage(
      id: legacy ? legacyMessageId : 'booking-deadline-message',
      conversationId: 'booking-deadline-conversation',
      senderId: 'renter',
      message: bookingData.toChatMessagePayload(),
      createdAt: DateTime(2099, 11, 26),
      isMine: onRetryCustomerRequest != null,
      isRead: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BookingRequestBubbleCard(
              message: message,
              bookingData: bookingData,
              isOwner: onRetryCustomerRequest == null,
              onRetryCustomerRequest: onRetryCustomerRequest,
            ),
          ),
        ),
      ),
    );
  }

  for (final (status, label) in [
    ('completed', 'การเช่าเสร็จสิ้น'),
    ('confirmed', 'รายละเอียดนัดรับ'),
  ]) {
    testWidgets('a saved confirmation stays visible while checking $status', (
      tester,
    ) async {
      final response = Completer<Map<String, Object>>();
      bookingResponse = response;
      addTearDown(() {
        if (!response.isCompleted) {
          response.complete({'id': 36, 'status': status});
        }
        bookingResponse = null;
      });

      await pumpCard(tester, status: 'confirmed');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('ดูรายละเอียดสินค้า'), findsOneWidget);
      expect(find.text('ยืนยันคำขอเช่าเรียบร้อยแล้ว'), findsOneWidget);
      expect(
        find.text('ยืนยันเรียบร้อยแล้ว รอนัดรับและส่งมอบอุปกรณ์'),
        findsOneWidget,
      );
      final pickupButton = find.widgetWithText(
        ElevatedButton,
        'รายละเอียดนัดรับ',
      );
      final button = tester.widget<ElevatedButton>(pickupButton);
      expect(
        button.style?.backgroundColor?.resolve({
          if (!button.enabled) WidgetState.disabled,
        }),
        AppColors.primaryColor,
      );
      await tester.ensureVisible(pickupButton);
      await tester.tap(pickupButton);
      await tester.tap(pickupButton);
      await tester.pump();
      final pickupPage = find.byType(RentalTrackingMapPage);
      expect(pickupPage, findsNothing);

      response.complete({'id': 36, 'status': status});
      await tester.pumpAndSettle();
      if (status == 'completed') {
        expect(find.text(label), findsOneWidget);
        expect(pickupButton, findsNothing);
        expect(pickupPage, findsNothing);
      } else {
        expect(pickupPage, findsOneWidget);
        expect(tester.widget<RentalTrackingMapPage>(pickupPage).bookingId, 36);
        Navigator.of(tester.element(pickupPage)).pop();
        await tester.pumpAndSettle();
        expect(pickupPage, findsNothing);
        expect(find.text(label), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (status, label, color) in [
    ('pending', 'ตรวจสอบและยืนยันคำขอเช่า', AppColors.primaryColor),
    ('active', 'ตรวจรับคืนอุปกรณ์ & ตรวจสภาพ', const Color(0xFF10B981)),
  ]) {
    testWidgets('the $status action keeps its color while refreshing', (
      tester,
    ) async {
      final response = Completer<Map<String, Object>>();
      bookingResponse = response;
      addTearDown(() {
        if (!response.isCompleted) {
          response.complete({'id': 36, 'status': status});
        }
        bookingResponse = null;
      });

      await pumpCard(tester, status: status);
      await tester.pump(const Duration(milliseconds: 300));
      final action = find.widgetWithText(ElevatedButton, label);
      final button = tester.widget<ElevatedButton>(action);
      expect(
        button.style?.backgroundColor?.resolve({
          if (!button.enabled) WidgetState.disabled,
        }),
        color,
      );

      response.complete({'id': 36, 'status': status});
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(action).enabled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final startsPending in [false, true]) {
    testWidgets(
      'retry appears with the cancellation status (starts pending: $startsPending)',
      (tester) async {
        final response = Completer<Map<String, Object>>();
        bookingResponse = response;
        final responseStatus = startsPending ? 'pending' : 'cancelled';
        addTearDown(() {
          if (!response.isCompleted) {
            response.complete({'id': 36, 'status': responseStatus});
          }
          bookingResponse = null;
        });
        var retries = 0;
        void onRetry() => retries++;
        final retry = find.widgetWithText(TextButton, 'ส่งคำขอเช่าใหม่');
        final cancelled = find.text('ยกเลิกการเช่าแล้ว');
        if (startsPending) {
          await pumpCard(
            tester,
            status: 'pending',
            onRetryCustomerRequest: onRetry,
          );
          await tester.pump();
          expect(retry, findsNothing);
        }

        await pumpCard(
          tester,
          status: 'cancelled',
          onRetryCustomerRequest: onRetry,
        );
        expect(cancelled, findsOneWidget);
        expect(retry, findsOneWidget);
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        expect(retries, 1);

        response.complete({'id': 36, 'status': responseStatus});
        await tester.pumpAndSettle();
        expect(cancelled, findsOneWidget);
        expect(retry, findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a stale chat update does not replace a completed status', (
    tester,
  ) async {
    final response = Completer<Map<String, Object>>();
    bookingResponse = response;
    addTearDown(() {
      response.complete({'id': 36, 'status': 'completed'});
      bookingResponse = null;
    });

    await pumpCard(tester, status: 'completed');
    expect(find.text('การเช่าเสร็จสิ้น'), findsOneWidget);

    await pumpCard(tester, status: 'confirmed');
    expect(find.text('การเช่าเสร็จสิ้น'), findsOneWidget);
    expect(find.text('รายละเอียดนัดรับ'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a booking ID saved locally also waits for the current status', (
    tester,
  ) async {
    final response = Completer<Map<String, Object>>();
    bookingResponse = response;
    addTearDown(() {
      if (!response.isCompleted) {
        response.complete({'id': 36, 'status': 'completed'});
      }
      bookingResponse = null;
    });
    await BookingConfirmationTracker.markConfirmed(
      messageId: legacyMessageId,
      bookingId: 36,
    );
    await BookingConfirmationTracker.setStatus(
      messageId: legacyMessageId,
      status: 'confirmed',
    );

    await pumpCard(tester, legacy: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('รายละเอียดนัดรับ'), findsNothing);

    response.complete({'id': 36, 'status': 'completed'});
    await tester.pumpAndSettle();
    expect(find.text('การเช่าเสร็จสิ้น'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a failed lookup keeps pickup disabled until completion arrives',
    (tester) async {
      final response = Completer<Map<String, Object>>();
      bookingResponse = response;
      addTearDown(() => bookingResponse = null);

      await pumpCard(tester, status: 'confirmed');
      await tester.pump(const Duration(milliseconds: 300));
      final pickupButton = find.widgetWithText(
        ElevatedButton,
        'รายละเอียดนัดรับ',
      );
      await tester.ensureVisible(pickupButton);
      await tester.tap(pickupButton);
      await tester.pump();

      response.completeError(StateError('Temporary request failure'));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(pickupButton).onPressed, isNull);
      expect(find.byType(RentalTrackingMapPage), findsNothing);
      expect(find.text('ยืนยันคำขอเช่าเรียบร้อยแล้ว'), findsOneWidget);
      expect(find.text('ตรวจสอบสถานะการเช่าไม่สำเร็จ'), findsOneWidget);

      final completedResponse = Completer<Map<String, Object>>();
      bookingResponse = completedResponse;
      await pumpCard(tester, status: 'completed');
      expect(find.text('การเช่าเสร็จสิ้น'), findsOneWidget);
      completedResponse.complete({'id': 36, 'status': 'completed'});
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('retry restores pickup only after a successful lookup', (
    tester,
  ) async {
    final firstResponse = Completer<Map<String, Object>>();
    bookingResponse = firstResponse;
    addTearDown(() => bookingResponse = null);
    await pumpCard(tester, status: 'confirmed');
    await tester.pump(const Duration(milliseconds: 300));
    firstResponse.completeError(StateError('Temporary request failure'));
    await tester.pumpAndSettle();

    final retryResponse = Completer<Map<String, Object>>();
    bookingResponse = retryResponse;
    final retryButton = find.widgetWithText(
      OutlinedButton,
      'ลองตรวจสอบอีกครั้ง',
    );
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);
    await tester.pump();
    final pickupButton = find.widgetWithText(
      ElevatedButton,
      'รายละเอียดนัดรับ',
    );
    expect(tester.widget<ElevatedButton>(pickupButton).onPressed, isNotNull);

    retryResponse.complete({'id': 36, 'status': 'confirmed'});
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดนัดรับ'), findsOneWidget);
    expect(retryButton, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the active chat card shows the return deadline in local time', (
    tester,
  ) async {
    await pumpCard(tester);
    await tester.pumpAndSettle();

    final deadline = tester.widget<Text>(find.textContaining('ครบกำหนดส่งคืน'));
    expect(deadline.data, 'ครบกำหนดส่งคืน: 27/11/2099 เวลา 17:00 น.');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
