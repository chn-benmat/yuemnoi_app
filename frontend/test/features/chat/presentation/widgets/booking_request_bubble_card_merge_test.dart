import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/booking_request_bubble_card.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('th', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookingConfirmationTracker.clearMemoryCache();
  });

  tearDown(BookingConfirmationTracker.clearMemoryCache);

  Future<void> pumpCard(
    WidgetTester tester, {
    String? initialStatus,
    bool isOwner = false,
    bool isHandoverCompleted = false,
    String? bookingStatus,
    bool customerRequest = false,
    bool canCloseConfirmation = false,
  }) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final bookingData = BookingRequestData(
      item: const BookingItemInfo(
        id: 1,
        title: 'Camera',
        imageUrl: '',
        rating: 4.8,
        reviewCount: 12,
        hourlyRate: 150,
        dailyRate: 700,
        defaultLocation: 'Pickup point',
      ),
      startDate: tomorrow,
      endDate: tomorrow.add(const Duration(days: 1)),
      startTime: const TimeOfDay(hour: 10, minute: 0),
      endTime: const TimeOfDay(hour: 10, minute: 0),
      location: 'Pickup point',
      locationAddress: '123 Siam Square, Bangkok',
      latitude: 13.7466,
      longitude: 100.5393,
      status: bookingStatus,
      isCustomerRequest: customerRequest,
      bookingId: customerRequest ? 36 : null,
    );
    final message = ChatMessage(
      id: 'merge-regression-message',
      conversationId: 'merge-regression-conversation',
      senderId: 'renter',
      message: bookingData.toChatMessagePayload(),
      createdAt: DateTime.now(),
      isMine: !customerRequest || !isOwner,
      isRead: true,
    );

    final home = Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: BookingRequestBubbleCard(
            message: message,
            bookingData: bookingData,
            isOwner: isOwner,
            initialStatus: initialStatus,
            isHandoverCompleted: isHandoverCompleted,
          ),
        ),
      ),
    );
    if (canCloseConfirmation) {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => home),
          GoRoute(
            path: AppRoutes.bookingConfirmation,
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(false),
                child: const Text('ปิดคำขอ'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    } else {
      await tester.pumpWidget(MaterialApp(home: home));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('only the owner can confirm a pending customer request', (
    tester,
  ) async {
    const label = 'ตรวจสอบและยืนยันคำขอเช่า';
    await pumpCard(tester, bookingStatus: 'pending', customerRequest: true);
    expect(find.text('รอผู้ปล่อยเช่ายืนยันคำขอ'), findsOneWidget);
    expect(find.text(label), findsNothing);
    expect(find.text('แก้ไขรายละเอียด'), findsOneWidget);

    await pumpCard(
      tester,
      bookingStatus: 'pending',
      customerRequest: true,
      isOwner: true,
    );
    expect(find.text(label), findsOneWidget);
    expect(find.text('แก้ไขรายละเอียด'), findsNothing);

    await pumpCard(tester, bookingStatus: 'confirmed', customerRequest: true);
    expect(find.text('แก้ไขรายละเอียด'), findsNothing);
  });

  testWidgets('closing the owner review leaves the customer request pending', (
    tester,
  ) async {
    await BookingConfirmationTracker.markConfirmed(
      messageId: 'merge-regression-message',
      bookingId: 36,
    );
    await pumpCard(
      tester,
      bookingStatus: 'pending',
      customerRequest: true,
      isOwner: true,
      canCloseConfirmation: true,
    );
    final review = find.text('ตรวจสอบและยืนยันคำขอเช่า');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปิดคำขอ'));
    await tester.pumpAndSettle();

    expect(review, findsOneWidget);
    expect(find.text('รายละเอียดนัดรับ'), findsNothing);
  });

  for (final owner in [true, false]) {
    testWidgets(
      'completed rental status in the card is read-only for owner=$owner',
      (tester) async {
        await pumpCard(
          tester,
          initialStatus: 'completed',
          isOwner: owner,
          isHandoverCompleted: true,
        );
        final completedStatus = find.text('การเช่าเสร็จสิ้น');
        expect(completedStatus, findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-booking-return-button')),
          findsNothing,
        );
        await tester.ensureVisible(completedStatus);
        await tester.tap(completedStatus);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('รายละเอียดสถานะการเช่า'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('confirmed booking keeps pickup details for owner=$owner', (
      tester,
    ) async {
      await pumpCard(tester, initialStatus: 'confirmed', isOwner: owner);
      expect(find.text('รายละเอียดนัดรับ'), findsOneWidget);
      expect(
        find.textContaining(owner ? 'ดูสถานะปล่อยเช่า' : 'ดูสถานะการเช่า'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final status in ['active', 'awaiting_return', 'return_ready']) {
      testWidgets('$status keeps the return action for owner=$owner', (
        tester,
      ) async {
        await pumpCard(tester, initialStatus: status, isOwner: owner);
        expect(
          find.byKey(const ValueKey('chat-booking-return-button')),
          findsOneWidget,
        );
        expect(
          find.textContaining(owner ? 'ดูสถานะปล่อยเช่า' : 'ดูสถานะการเช่า'),
          findsNothing,
        );
        expect(find.text('ดูจุดนัดส่งคืนบนแผนที่'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('pending booking renders one rental details table', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.text('เวลาเช่า'), findsOneWidget);
    expect(find.text('จุดนัดพบ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-booking-return-button')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opens pickup details for an offer without a booking ID', (
    tester,
  ) async {
    AuthSession.saveAccessToken('test-token');
    addTearDown(AuthSession.clear);
    await pumpCard(tester, bookingStatus: 'pending', isOwner: true);

    final pickup = find.text('จุดนัดพบ');
    await tester.ensureVisible(pickup);
    await tester.tap(pickup);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('ไม่พบรายการเช่านี้ กรุณาเปิดหน้าจากรายการเช่าของคุณ'),
      findsNothing,
    );
    expect(find.text('นัดรับอุปกรณ์'), findsOneWidget);
    expect(find.text('123 Siam Square, Bangkok'), findsOneWidget);
    expect(find.text('โทรหาผู้เช่า'), findsNothing);
    expect(find.text('ส่งมอบอุปกรณ์'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a previous handover does not confirm a new pending offer', (
    tester,
  ) async {
    await pumpCard(
      tester,
      bookingStatus: 'pending',
      isOwner: true,
      isHandoverCompleted: true,
    );

    expect(find.text('แก้ไขรายละเอียด'), findsOneWidget);
    expect(find.text('รายละเอียดนัดรับ'), findsNothing);
    expect(find.text('ดูสถานะปล่อยเช่า'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelled booking cannot be accepted again', (tester) async {
    await pumpCard(tester, initialStatus: 'cancelled');
    final cancelledStatus = find.text('ยกเลิกการเช่าแล้ว');
    expect(cancelledStatus, findsOneWidget);
    expect(
      find.ancestor(of: cancelledStatus, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('chat-booking-action-button')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('daily offer shows dates without clock times or sender wording', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('รายละเอียดคำขอเช่า'), findsOneWidget);
    expect(find.textContaining('เวลา 10:00'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'confirmation arriving for the same offer replaces the edit action',
    (tester) async {
      await pumpCard(tester);
      await pumpCard(tester, initialStatus: 'confirmed');
      expect(find.text('รายละเอียดนัดรับ'), findsOneWidget);
      expect(find.text('แก้ไขรายละเอียด'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
