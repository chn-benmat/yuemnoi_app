import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/booking_confirmation_tracker.dart';
import 'package:frontend/core/widgets/rental_countdown_timer_widget.dart';
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
  });

  tearDown(() {
    BookingConfirmationTracker.clearMemoryCache();
  });

  testWidgets('BookingRequestBubbleCard pumps and builds without crash or overflow', (tester) async {
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
    );

    final message = ChatMessage(
      id: 'msg-test-1',
      conversationId: 'conv-1',
      senderId: 'user-1',
      message: bookingData.toChatMessagePayload(),
      createdAt: now.subtract(const Duration(days: 3)),
      isMine: true,
      isRead: true,
    );

    await BookingConfirmationTracker.markConfirmed(messageId: 'msg-test-1', bookingId: 101);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: BookingRequestBubbleCard(
                message: message,
                bookingData: bookingData,
                senderName: 'Test User',
                isOwner: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(BookingRequestBubbleCard), findsOneWidget);
    // ตรวจสอบว่าชิปจำลองสแกน/PIN ถูกนำออกแล้ว
    expect(find.textContaining('จำลองสแกน/PIN'), findsNothing);
    expect(find.text('รายละเอียดนัดรับ'), findsOneWidget);

    // ทำความสะอาด widget แรก
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // ทดสอบสร้าง BookingRequestBubbleCard ในสถานะ active
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: BookingRequestBubbleCard(
                message: message,
                bookingData: bookingData,
                senderName: 'Test User',
                isOwner: false,
                initialStatus: 'active',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // ตรวจสอบว่าไม่มี RentalCountdownTimerWidget ใน Bubble card อีกต่อไป (เปลี่ยนไปแจ้งเตือนทาง notification แทน)
    expect(find.byType(RentalCountdownTimerWidget), findsNothing);

    // ตรวจสอบว่ามีข้อมูล "เวลาเช่า" และ "ครบกำหนดเมื่อ" ตามที่ต้องการ
    expect(find.text('เวลาเช่า'), findsOneWidget);
    expect(find.text('ครบกำหนดเมื่อ'), findsOneWidget);
    expect(find.text('เริ่มการเช่าแล้ว • แจ้งเตือนเวลาผ่านการแจ้งเตือน'), findsOneWidget);

    // ตรวจสอบปุ่ม "ส่งคืนอุปกรณ์" กดแล้วไม่ไปไหน ไม่เปิดหน้า/โมดอลคืนของ
    expect(find.text('ส่งคืนอุปกรณ์'), findsOneWidget);
    await tester.tap(find.text('ส่งคืนอุปกรณ์'));
    await tester.pump();
    expect(find.textContaining('Checklist ตรวจรับของคืน'), findsNothing);
    expect(find.textContaining('ส่งคืนอุปกรณ์ & จบการเช่า'), findsNothing);

    // ทำความสะอาด widget เพื่อยกเลิก ticker timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('RentalCountdownTimerWidget within narrow 270px width constraint does not overflow', (tester) async {
    final now = DateTime.now();
    // จำลองกรณี overdue มากกว่า 90 ชั่วโมง
    final pastDate = now.subtract(const Duration(hours: 90, minutes: 15, seconds: 20));

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
  });
}
