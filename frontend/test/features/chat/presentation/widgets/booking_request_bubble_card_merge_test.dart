import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/presentation/widgets/booking_request_bubble_card.dart';
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

  Future<void> pumpCard(WidgetTester tester, {String? initialStatus}) async {
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
    );
    final message = ChatMessage(
      id: 'merge-regression-message',
      conversationId: 'merge-regression-conversation',
      senderId: 'renter',
      message: bookingData.toChatMessagePayload(),
      createdAt: DateTime.now(),
      isMine: true,
      isRead: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: BookingRequestBubbleCard(
                message: message,
                bookingData: bookingData,
                isOwner: false,
                initialStatus: initialStatus,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
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

  testWidgets('initial active status exposes the return action', (
    tester,
  ) async {
    await pumpCard(tester, initialStatus: 'active');

    expect(
      find.byKey(const ValueKey('chat-booking-return-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

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
