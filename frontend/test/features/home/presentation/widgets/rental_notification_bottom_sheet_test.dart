import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/presentation/widgets/rental_notification_bottom_sheet.dart';
import 'package:frontend/features/profile/domain/entities/rental_booking.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('th', null);
  });

  group('RentalNotificationBottomSheet Tests', () {
    testWidgets('renders empty state when activeRentals is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RentalNotificationBottomSheet(activeRentals: []),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('การแจ้งเตือนเวลาเช่า'), findsOneWidget);
      expect(find.text('ไม่มีอุปกรณ์ที่ใกล้หมดเวลาในขณะนี้'), findsOneWidget);
      expect(find.text('ไปที่สถานะการเช่าทั้งหมด'), findsOneWidget);
    });

    testWidgets('renders active rental notification card', (tester) async {
      final futureDate = DateTime.now().add(const Duration(hours: 4));
      final item = RentalBooking(
        bookingId: 101,
        title: 'MacBook Air M2',
        partnerName: 'somchai',
        partnerRole: 'ผู้ปล่อยเช่า',
        status: 'กำลังเช่า',
        statusCode: 'active',
        endDate: futureDate,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RentalNotificationBottomSheet(activeRentals: [item]),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('การแจ้งเตือนเวลาเช่า'), findsOneWidget);
      expect(find.text('1 รายการ'), findsOneWidget);
      expect(find.text('MacBook Air M2'), findsOneWidget);
      expect(find.text('ผู้ปล่อยเช่า: somchai'), findsOneWidget);
      expect(find.text('⏳ กำลังเช่า'), findsOneWidget);
      expect(
        find.text('ใกล้ถึงกำหนดคืนแล้วนะ! เตรียมตัวส่งคืน'),
        findsOneWidget,
      );
      expect(find.text('ไปที่สถานะการเช่าทั้งหมด'), findsOneWidget);
    });

    testWidgets('renders overdue rental notification card', (tester) async {
      final pastDate = DateTime.now().subtract(
        const Duration(hours: 2, minutes: 30),
      );
      final item = RentalBooking(
        bookingId: 102,
        title: 'Sony A7 IV',
        partnerName: 'john',
        partnerRole: 'ผู้ปล่อยเช่า',
        status: 'เลยกำหนดคืน',
        statusCode: 'active',
        endDate: pastDate,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RentalNotificationBottomSheet(activeRentals: [item]),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sony A7 IV'), findsOneWidget);
      expect(find.text('⚠️ เลยกำหนด'), findsOneWidget);
      expect(
        find.text('เลยกำหนดส่งคืนแล้วนะ! กรุณานำส่งคืนทันที'),
        findsOneWidget,
      );
      expect(find.textContaining('เกินกำหนดมาแล้ว'), findsOneWidget);
    });
  });
}
