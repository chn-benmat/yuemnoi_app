import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_status_widgets.dart';

void main() {
  group('RentalStatusCard return deadlines', () {
    testWidgets(
      'shows the active badge and time remaining before the deadline',
      (tester) async {
        final now = DateTime.now();
        final futureEnd = now.add(const Duration(hours: 3, minutes: 15));
        final item = RentalStatusItemData(
          bookingId: 101,
          itemId: 50,
          title: 'ฟิกเกอร์ โกะโจ x เกะโท',
          ownerName: '6767',
          status: 'กำลังเช่า',
          statusCode: 'active',
          statusColor: const Color(0xFF7C3AED),
          iconData: Icons.inventory_2_outlined,
          duration: '1 วัน',
          totalPrice: 200,
          startDate: now.subtract(const Duration(hours: 21)),
          endDate: futureEnd,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: RentalStatusCard(item: item)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('กำลังใช้งาน'), findsOneWidget);
        expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
        expect(find.byIcon(Icons.warning_rounded), findsNothing);
        expect(
          find.textContaining(RegExp(r'^ครบกำหนด: .+ \(เหลืออีก 3 ชม\.')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows the overdue return warning in place of the active badge',
      (tester) async {
        final now = DateTime.now();
        final pastEnd = now.subtract(const Duration(minutes: 45));
        final item = RentalStatusItemData(
          bookingId: 102,
          itemId: 51,
          title: 'กล้อง Sony A7 IV',
          ownerName: 'ร้าน Bangkok Camera',
          status: 'กำลังเช่า',
          statusCode: 'active',
          statusColor: const Color(0xFF7C3AED),
          iconData: Icons.camera_alt_outlined,
          duration: '2 วัน',
          totalPrice: 1500,
          startDate: now.subtract(const Duration(days: 2, hours: 1)),
          endDate: pastEnd,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: RentalStatusCard(item: item)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('กำลังใช้งาน'), findsNothing);
        expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(
          find.textContaining(
            RegExp(r'^เลยกำหนดส่งคืนแล้ว [0-9]+ นาที \(กรุณาส่งคืนด่วน\)$'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
