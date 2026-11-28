import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/services/phone_call_service.dart';
import 'package:frontend/features/chat/domain/entities/chat_conversation.dart';
import 'package:frontend/features/profile/data/datasources/rental_contact_remote_data_source.dart';
import 'package:frontend/features/profile/domain/entities/rental_handover_payment.dart';
import 'package:frontend/features/profile/domain/usecases/update_booking_status_usecase.dart';
import 'package:frontend/features/profile/presentation/pages/rentals/rental_handover_page.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactSource extends RentalContactRemoteDataSource {
  int? requestedBooking;
  ChatConversation? conversation;

  @override
  Future<ChatConversation?> getConversation({
    int? bookingId,
    String? conversationId,
  }) async {
    requestedBooking = bookingId;
    return conversation;
  }

  @override
  Future<String> getPhone({int? bookingId, String? conversationId}) async {
    requestedBooking = bookingId;
    return '+66987654321';
  }
}

class RecordingPhoneCall implements PhoneCallService {
  final numbers = <String>[];
  @override
  Future<bool> call(String phoneNumber) async {
    numbers.add(phoneNumber);
    return true;
  }
}

class HandoverStatus extends Fake implements UpdateBookingStatusUseCase {
  bool active = false;

  @override
  Future<RentalHandoverPayment> handoverPayment({
    required int bookingId,
    bool confirm = false,
    String? promptPayPhone,
    String? promptPayNationalId,
  }) async {
    if (confirm) active = true;
    return RentalHandoverPayment(
      status: active ? 'active' : 'confirmed',
      paymentMethod: 'cash',
      paymentConfirmed: active,
      totalSatang: 150000,
    );
  }
}

void main() {
  for (final isOwner in [false, true]) {
    testWidgets('calls actual partner phone when isOwner=$isOwner', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final contact = ContactSource();
      final phone = RecordingPhoneCall();
      await tester.pumpWidget(
        MaterialApp(
          home: RentalHandoverPage(
            contactDataSource: contact,
            phoneCallService: phone,
            bookingId: 25,
            isOwner: isOwner,
            ownerPhone: '0812345678',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(isOwner ? 'โทรหาผู้เช่า' : 'โทรหาเจ้าของ'));
      await tester.pump();
      expect(contact.requestedBooking, 25);
      expect(phone.numbers, ['+66987654321']);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (description, isOwner, openPayment) in [
    ('lender confirming receipt', true, true),
    ('renter in the payment sheet', false, true),
    ('renter on the pickup map', false, false),
  ]) {
    testWidgets('$description returns to the original chat', (tester) async {
      const bookingId = 25;
      SharedPreferences.setMockInitialValues({
        'handover_progress_step_booking_$bookingId': 1,
      });
      final handover = HandoverStatus();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => RentalHandoverPage(
                      bookingId: bookingId,
                      isOwner: isOwner,
                      startDate: DateTime(2020),
                      returnToPreviousChat: true,
                      updateBookingStatusUseCase: handover,
                    ),
                  ),
                ),
                child: const Text('Open pickup from chat'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open pickup from chat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      if (openPayment) {
        await tester.tap(
          find.text(isOwner ? 'ยืนยันการรับเงิน' : 'ดูสถานะนัดรับ'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      if (isOwner) {
        final button = find.text('ยืนยันว่าได้รับเงินครบถ้วนแล้ว [฿1500]');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.widgetWithText(ElevatedButton, 'ยืนยัน'));
      } else {
        handover.active = true;
      }
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RentalHandoverPage), findsNothing);
      expect(find.text('Open pickup from chat').hitTestable(), findsOneWidget);
    });
  }

  testWidgets('payment from rental status opens the associated chat', (
    tester,
  ) async {
    final handover = HandoverStatus();
    final contact = ContactSource()
      ..conversation = const ChatConversation(
        id: 'rental-conversation',
        otherUserId: 'lender',
        name: 'Lender',
        role: ChatParticipantRole.owner,
        avatarAsset: '',
        preview: '',
        timeLabel: '',
      );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => RentalHandoverPage(
                    bookingId: 27,
                    startDate: DateTime(2020),
                    contactDataSource: contact,
                    updateBookingStatusUseCase: handover,
                  ),
                ),
              ),
              child: const Text('Open pickup from rental status'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.chatDetail,
          builder: (_, state) =>
              Scaffold(body: Text((state.extra as ChatConversation).id)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open pickup from rental status'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    handover.active = true;
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(contact.requestedBooking, 27);
    expect(find.text('rental-conversation').hitTestable(), findsOneWidget);
    expect(find.byType(RentalHandoverPage, skipOffstage: false), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open pickup from rental status'), findsOneWidget);
  });

  testWidgets('resuming pickup without a known payment method shows status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'handover_progress_step_booking_930': 1,
    });
    await tester.pumpWidget(
      MaterialApp(home: RentalHandoverPage(bookingId: 930, isOwner: false)),
    );
    await tester.pump();
    expect(find.text('ดูสถานะนัดรับ'), findsOneWidget);
    expect(find.text('ชำระเงิน'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing contact never uses a sample phone number', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RentalHandoverPage(isOwner: false)),
    );
    await tester.pump();
    await tester.tap(find.text('โทรหาเจ้าของ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ไม่พบข้อมูลติดต่อของรายการเช่านี้'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final bookingId in <int?>[null, 25]) {
    testWidgets('guards handover details (ID: $bookingId)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RentalHandoverPage(
            requireBookingId: true,
            bookingId: bookingId,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          bookingId == null
              ? 'ไม่พบรายการเช่านี้ กรุณาเปิดหน้าจากรายการเช่าของคุณ'
              : 'กรุณาเข้าสู่ระบบเพื่อดูรายละเอียดนัดรับ',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
