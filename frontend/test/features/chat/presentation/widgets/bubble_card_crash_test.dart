import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:frontend/core/widgets/rental_countdown_timer_widget.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/booking_request_bubble_card.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_tracking_map_page.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('th', null);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    BookingConfirmationTracker.clearMemoryCache();
  });

  testWidgets('confirmed rental opens the pickup route directly from chat', (
    tester,
  ) async {
    final start = DateTime(2026, 11, 24);
    final bookingData = BookingRequestData(
      item: const BookingItemInfo(
        id: 1,
        title: 'กล้องทดสอบ',
        imageUrl: '',
        rating: 5,
        reviewCount: 1,
        hourlyRate: 150,
        dailyRate: 700,
        defaultLocation: 'เซ็นทรัลเวิลด์',
      ),
      rentalType: BookingRentalType.hourly,
      startDate: start,
      endDate: start,
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 17, minute: 0),
      location: 'เซ็นทรัลเวิลด์',
      bookingId: 2072,
      status: 'confirmed',
      paymentMethod: 'promptpay',
    );
    final message = ChatMessage(
      id: '71',
      conversationId: 'conv-1',
      senderId: 'owner-1',
      message: bookingData.toChatMessagePayload(),
      createdAt: start,
      isMine: false,
      isRead: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BookingRequestBubbleCard(
              message: message,
              bookingData: bookingData,
              isOwner: false,
            ),
          ),
        ),
      ),
    );
    final pickupDetails = find.text('รายละเอียดนัดรับ');
    await tester.ensureVisible(pickupDetails);
    await tester.tap(pickupDetails);
    await tester.pumpAndSettle();

    final mapPage = find.byType(RentalTrackingMapPage);
    expect(mapPage, findsOneWidget);
    final map = tester.widget<RentalTrackingMapPage>(mapPage);
    expect(map.bookingData?.bookingId, 2072);
    expect(map.bookingData?.conversationId, 'conv-1');
    expect(map.bookingData?.location, 'เซ็นทรัลเวิลด์');
    expect(map.bookingData?.paymentMethod, 'promptpay');

    Navigator.of(tester.element(mapPage)).pop();
    await tester.pumpAndSettle();
    expect(pickupDetails, findsOneWidget);
  });

  testWidgets(
    'a handed-over rental shows the new deadline and opens its return route',
    (tester) async {
      final now = DateTime.now();
      // จำลองกรณีที่ผู้ใช้จองไว้เมื่อ 3 วันก่อน และเพิ่งกดยืนยันเริ่มเช่าวันนี้
      final bookingData = BookingRequestData(
        item: const BookingItemInfo(
          id: 1,
          title: 'Sony Alpha a7 IV',
          imageUrl: '',
          rating: 4.8,
          reviewCount: 12,
          hourlyRate: 150,
          dailyRate: 700,
          defaultLocation: 'Siam Paragon',
        ),
        startDate: now.subtract(const Duration(days: 3)),
        endDate: now.subtract(const Duration(days: 2)),
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 18, minute: 0),
        location: 'Siam Paragon',
        bookingId: 101,
        status: 'confirmed',
      );

      ChatMessage messageFor(BookingRequestData data) => ChatMessage(
        id: 'msg-test-1',
        conversationId: 'conv-1',
        senderId: 'user-1',
        message: data.toChatMessagePayload(),
        createdAt: now.subtract(const Duration(days: 3)),
        isMine: false,
        isRead: true,
      );

      final booking = ValueNotifier(bookingData);
      addTearDown(booking.dispose);
      String? returnRentalId;
      Object? returnRole;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: ValueListenableBuilder<BookingRequestData>(
                    valueListenable: booking,
                    builder: (_, data, _) => BookingRequestBubbleCard(
                      message: messageFor(data),
                      bookingData: data,
                      senderName: 'Test User',
                      isOwner: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.rentalReturn,
            builder: (_, state) {
              returnRentalId = state.pathParameters['rentalId'];
              returnRole = state.extra;
              return const Scaffold(body: Text('หน้าคืนอุปกรณ์ทดสอบ'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byType(BookingRequestBubbleCard), findsOneWidget);
      expect(find.textContaining('จำลองสแกน/PIN'), findsNothing);
      expect(find.text('รายละเอียดนัดรับ'), findsOneWidget);
      expect(find.text('เวลาเช่า'), findsOneWidget);

      final handoverAt = now.subtract(const Duration(hours: 1));
      await BookingConfirmationTracker.markHandoverStarted(
        bookingId: 101,
        startTime: handoverAt,
      );
      booking.value = bookingData.copyWith(status: 'active');
      await tester.pumpAndSettle();

      expect(find.text('รายละเอียดนัดรับ'), findsNothing);
      expect(find.text('ระยะเวลาการเช่าที่เหลือ'), findsOneWidget);
      final returnDeadline = DateFormat(
        'dd/MM/yyyy เวลา HH:mm น.',
      ).format(handoverAt.add(const Duration(days: 1)));
      expect(find.text('ครบกำหนดส่งคืน: $returnDeadline'), findsOneWidget);

      final returnButton = find.text('ส่งคืนอุปกรณ์');
      await tester.ensureVisible(returnButton);
      await tester.tap(returnButton);
      await tester.pumpAndSettle();
      expect(find.text('หน้าคืนอุปกรณ์ทดสอบ'), findsOneWidget);
      expect(returnRentalId, '101');
      expect(returnRole, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RentalCountdownTimerWidget within narrow 270px width constraint does not overflow',
    (tester) async {
      final now = DateTime.now();
      // จำลองกรณี overdue มากกว่า 90 ชั่วโมง
      final pastDate = now.subtract(
        const Duration(hours: 90, minutes: 15, seconds: 20),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 270, // แคบเป็นพิเศษ เพื่อทดสอบ layout robust
                child: RentalCountdownTimerWidget(
                  endDateTime: pastDate,
                  hourlyLateFee: 100,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(RentalCountdownTimerWidget), findsOneWidget);

      // ทำความสะอาด widget เพื่อยกเลิก ticker timer
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
