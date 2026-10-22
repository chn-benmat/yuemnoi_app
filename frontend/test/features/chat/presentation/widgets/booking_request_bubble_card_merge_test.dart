import 'package:go_router/go_router.dart';
import 'package:frontend/core/navigation/app_routes.dart';
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

  Future<void> pumpCard(
    WidgetTester tester, {
    String? initialStatus,
    bool isOwner = false,
    bool isHandoverCompleted = false,
    void Function(String)? onRoute,
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
    if (onRoute == null) {
      await tester.pumpWidget(MaterialApp(home: home));
    } else {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => home),
          GoRoute(
            path: AppRoutes.rentalStatus,
            builder: (_, state) {
              onRoute(state.uri.toString());
              return const Scaffold(body: Text('rental-status-destination'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => child!,
        ),
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  for (final owner in [true, false]) {
    testWidgets(
      'completed rental stays completed after handover for owner=$owner',
      (tester) async {
        await pumpCard(
          tester,
          initialStatus: 'completed',
          isOwner: owner,
          isHandoverCompleted: true,
        );
        expect(find.text('การเช่าเสร็จสิ้น'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-booking-return-button')),
          findsNothing,
        );
        final completedButton = find.byKey(
          const ValueKey('chat-booking-rental-status-button'),
        );
        await tester.ensureVisible(completedButton);
        await tester.tap(completedButton);
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียดสถานะการเช่า'), findsOneWidget);
        expect(find.text('เสร็จสิ้น'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('status action follows owner=$owner', (tester) async {
      String? destination;
      await pumpCard(
        tester,
        initialStatus: 'confirmed',
        isOwner: owner,
        onRoute: (uri) => destination = uri,
      );
      expect(
        find.text(owner ? 'ดูสถานะปล่อยเช่า' : 'ดูสถานะการเช่า'),
        findsOneWidget,
      );
      final button = find.byKey(
        const ValueKey('chat-booking-rental-status-button'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        destination,
        owner
            ? '${AppRoutes.rentalStatus}?role=lender'
            : AppRoutes.rentalStatus,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
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

  for (final status in ['active', 'awaiting_return', 'return_ready']) {
    testWidgets('$status exposes the canonical return action', (tester) async {
      await pumpCard(tester, initialStatus: status);
      expect(
        find.byKey(const ValueKey('chat-booking-return-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('cancelled booking cannot be accepted again', (tester) async {
    await pumpCard(tester, initialStatus: 'cancelled');
    expect(find.text('ยกเลิกการเช่าแล้ว • ดูสถานะการเช่า'), findsOneWidget);
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
