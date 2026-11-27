import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/booking/presentation/pages/booking_request_page.dart';
import 'package:frontend/features/booking/presentation/widgets/booking_location_card.dart';
import 'package:frontend/features/booking/presentation/widgets/booking_time_range_picker.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('th'));

  testWidgets('owner can correct a past queue offer before saving', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final data = BookingRequestData(
      item: BookingItemInfo.defaultMockItem.copyWith(imageUrl: ''),
      rentalType: BookingRentalType.hourly,
      startDate: yesterday,
      endDate: yesterday,
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 17, minute: 0),
      location: 'สถานที่เดิม',
      rentalQueueMessageId: 660,
      originalMessageId: '663',
      conversationId: 'room',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BookingRequestPage(initialData: data, isEditMode: true),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byKey(const ValueKey('submit-booking-request-button'));
    final confirm = find.byKey(
      const ValueKey('confirm-send-booking-request-button'),
    );
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(confirm, findsNothing);
    expect(
      find.text('เวลาเริ่มเช่าผ่านไปแล้ว กรุณาเลือกวันและเวลาเริ่มเช่าใหม่'),
      findsOneWidget,
    );
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();

    final periodPicker = tester.widget<BookingTimeRangePicker>(
      find.byType(BookingTimeRangePicker),
    );
    periodPicker.onDatesChanged!(tomorrow, tomorrow);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(confirm, findsOneWidget);
    expect(find.textContaining('09:00 น. - 17:00 น., 8 ชม.'), findsOneWidget);
  });

  testWidgets(
    'editing keeps the existing location without requiring coordinates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = BookingRequestData(
        item: BookingItemInfo.defaultMockItem.copyWith(imageUrl: ''),
        startDate: DateTime(2026, 11, 19),
        endDate: DateTime(2026, 11, 20),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 10, minute: 0),
        location: 'สถานที่เดิม',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BookingRequestPage(initialData: data, isEditMode: true),
        ),
      );
      await tester.pumpAndSettle();
      final location = tester.widget<BookingLocationCard>(
        find.byType(BookingLocationCard),
      );
      expect(location.location, 'สถานที่เดิม');
      expect(location.isEditable, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('submit-booking-request-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('กรุณาเลือกสถานที่นัดพบ'), findsNothing);
      expect(
        find.byKey(const ValueKey('confirm-send-booking-request-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('confirming a customer edit reaches rental submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AuthSession.clear();
    final router = AppRoutes.createRouter(
      initialLocation: AppRoutes.termsOfService,
    );
    addTearDown(router.dispose);
    final tomorrow = DateUtils.dateOnly(
      DateTime.now(),
    ).add(const Duration(days: 1));
    final data = BookingRequestData(
      item: BookingItemInfo.defaultMockItem.copyWith(imageUrl: ''),
      rentalType: BookingRentalType.hourly,
      startDate: tomorrow,
      endDate: tomorrow,
      startTime: const TimeOfDay(hour: 14, minute: 0),
      endTime: const TimeOfDay(hour: 15, minute: 0),
      location: 'จุดนัดรับ',
      isCustomerRequest: true,
      bookingId: 25,
      conversationId: 'room',
      requestRevision: 2,
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    unawaited(
      AppRoutes.openBooking(
        tester.element(find.byType(Scaffold)),
        initialData: data,
        isEditMode: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('submit-booking-request-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-send-booking-request-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('กรุณาเข้าสู่ระบบก่อนส่งคำขอเช่า'), findsOneWidget);
  });

  testWidgets('confirming a rental returns to chat while saving is pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pendingSave = Completer<void>();
    addTearDown(() {
      if (!pendingSave.isCompleted) pendingSave.complete();
    });
    BookingRequestData? submitted;
    final data = BookingRequestData(
      item: const BookingItemInfo(
        id: 42,
        title: 'Canon EOS R50',
        imageUrl: '',
        rating: 0,
        reviewCount: 0,
        hourlyRate: 100,
        dailyRate: 500,
        defaultLocation: 'จุดนัดรับ',
      ),
      startDate: DateTime(2026, 10, 22),
      endDate: DateTime(2026, 10, 23),
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 9, minute: 0),
      location: 'จุดนัดรับ',
      latitude: 13.7,
      longitude: 100.5,
      conversationId: 'room',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BookingRequestPage(
                    initialData: data,
                    onSendRequest: (request) {
                      submitted = request;
                      unawaited(pendingSave.future);
                    },
                  ),
                ),
              ),
              child: const Text('เปิดคำขอ'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดคำขอ'));
    await tester.pumpAndSettle();
    for (final width in [320.0, 375.0, 414.0, 768.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'layout at $width px');
    }
    final submit = find.byKey(const ValueKey('submit-booking-request-button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final confirm = find.byKey(
      const ValueKey('confirm-send-booking-request-button'),
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(submitted?.item.id, 42);
    expect(pendingSave.isCompleted, isFalse);
    expect(find.byType(BookingRequestPage), findsNothing);
    expect(find.text('เปิดคำขอ'), findsOneWidget);
  });
}
