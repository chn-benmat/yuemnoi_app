import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/booking/presentation/pages/booking_request_page.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('th'));

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
