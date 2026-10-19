import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_handover_modal.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_return_modal.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_review_dialog.dart';

void main() {
  group('Rental Flow Modals and Dialogs', () {
    testWidgets(
      'Renter inspection exposes evidence-based cancellation before payment',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RentalHandoverModal(
                itemTitle: 'Sony A7 IV',
                ownerName: 'สมชาย',
                totalPrice: 1500,
                paymentMethod: 'promptpay',
                initialIsOwner: false,
              ),
            ),
          ),
        );

        // Verify title and item
        expect(find.text('ตรวจรับ & ชำระเงิน'), findsOneWidget);
        expect(find.text('Sony A7 IV'), findsOneWidget);

        expect(
          find.text('ยกเลิกการเช่า (สินค้ามีปัญหา / ไม่พร้อมใช้งาน)'),
          findsOneWidget,
        );
        expect(find.text('ไปยังการชำระเงิน'), findsOneWidget);
      },
    );

    testWidgets(
      'Legacy return entry delegates to canonical flow without mock completion',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RentalReturnModal(
                itemTitle: 'DJI Mini 4 Pro',
                ownerName: 'สมชาย',
                depositAmount: 2000,
                initialIsOwner: true,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(
          find.textContaining('กรุณาเลือกรายการเช่าที่ต้องการคืน'),
          findsWidgets,
        );
        expect(find.text('โอนคืนเงินประกัน'), findsNothing);
        expect(find.textContaining('รหัสตัวอย่าง'), findsNothing);
      },
    );

    testWidgets(
      'RentalReviewDialog allows star selection and comment submission',
      (tester) async {
        bool isSubmitted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      RentalReviewDialog.show(
                        context,
                        itemTitle: 'Sony A7 IV',
                        partnerName: 'สมชาย เจ้าของกล้อง',
                        onSubmit: () {
                          isSubmitted = true;
                        },
                      );
                    },
                    child: const Text('Open Review'),
                  );
                },
              ),
            ),
          ),
        );

        // Open dialog
        await tester.tap(find.text('Open Review'));
        await tester.pumpAndSettle();

        // Verify dialog contents
        expect(find.text('ให้คะแนนความประทับใจ'), findsOneWidget);
        expect(find.textContaining('สมชาย เจ้าของกล้อง'), findsOneWidget);
        expect(find.text('ตรงต่อเวลา'), findsOneWidget);

        // Select quick tag
        await tester.tap(find.text('ตรงต่อเวลา'));
        await tester.pumpAndSettle();

        // Enter comment
        await tester.enterText(
          find.byType(TextField),
          'บริการดีมาก อุปกรณ์ใช้งานได้สมบูรณ์',
        );
        await tester.pump();

        // Tap submit button
        await tester.tap(find.text('ส่งรีวิว'));
        await tester.pumpAndSettle();

        expect(isSubmitted, isTrue);
      },
    );
  });
}
