import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_status_widgets.dart';

void main() {
  group('RentalStatusCard Option 1 Time Status Box Tests', () {
    testWidgets(
      'renders green status box and normal badge when rental is within deadline',
      (tester) async {
        final futureEnd = DateTime.now().add(const Duration(hours: 3, minutes: 15));
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
          startDate: DateTime.now().subtract(const Duration(hours: 21)),
          endDate: futureEnd,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RentalStatusCard(item: item),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Badge displays กำลังเช่า
        expect(find.text('กำลังเช่า'), findsOneWidget);

        // 2. FaIcon is rendered in the Time Status Box
        expect(
          find.byWidgetPredicate(
            (w) => w is FaIcon && w.icon?.codePoint == FontAwesomeIcons.clock.codePoint,
          ),
          findsOneWidget,
        );

        // 3. Status text includes ครบกำหนด and เหลือเวลาอีก
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                w.data!.contains('ครบกำหนด') &&
                w.data!.contains('เหลือเวลาอีก'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'renders red status box and "เลยกำหนดคืน" badge when rental is past deadline',
      (tester) async {
        final pastEnd = DateTime.now().subtract(const Duration(minutes: 45));
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
          startDate: DateTime.now().subtract(const Duration(days: 2, hours: 1)),
          endDate: pastEnd,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RentalStatusCard(item: item),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Badge changes to เลยกำหนดคืน
        expect(find.text('เลยกำหนดคืน'), findsOneWidget);

        // 2. Exclamation icon is rendered in the Time Status Box
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is FaIcon &&
                w.icon?.codePoint ==
                    FontAwesomeIcons.triangleExclamation.codePoint,
          ),
          findsOneWidget,
        );

        // 3. Status text includes เลยกำหนดส่งคืนแล้ว and กรุณาส่งคืนด่วน
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                w.data!.contains('เลยกำหนดส่งคืนแล้ว') &&
                w.data!.contains('กรุณาส่งคืนด่วน'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
