import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_handover_modal.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_return_modal.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_review_dialog.dart';

void main() {
  group('Rental Flow Modals and Dialogs', () {
    testWidgets('RentalHandoverModal renders correctly and switches between Renter and Owner roles', (
      tester,
    ) async {
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

      // Verify role toggle
      expect(find.text('มุมมองผู้เช่า'), findsOneWidget);
      expect(find.text('ผู้ปล่อยเช่า'), findsOneWidget);

      // Verify checklist items
      expect(find.textContaining('เปิดติด'), findsOneWidget);
      expect(find.textContaining('อุปกรณ์เสริมครบถ้วน'), findsOneWidget);

      // Tap owner toggle
      await tester.tap(find.text('ผู้ปล่อยเช่า'));
      await tester.pumpAndSettle();

      // Proceed to Step 1 (Payment)
      final step1Btn = find.textContaining('ยืนยันการตรวจสภาพ');
      expect(step1Btn, findsOneWidget);
      await tester.tap(step1Btn);
      await tester.pumpAndSettle();

      // Verify PromptPay QR code box is visible for owner
      expect(find.textContaining('PromptPay:'), findsOneWidget);
      expect(find.textContaining('฿1500'), findsWidgets);
    });

    testWidgets('RentalReturnModal renders return checklist and deposit refund workflow', (
      tester,
    ) async {
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

      // Verify Return modal title
      expect(find.text('ส่งคืนอุปกรณ์ & จบการเช่า'), findsOneWidget);
      expect(find.text('DJI Mini 4 Pro'), findsOneWidget);

      // Checklist inspection
      expect(find.textContaining('เครื่องยังทำงานได้ปกติ'), findsOneWidget);
      expect(find.textContaining('อุปกรณ์เสริม'), findsOneWidget);

      // Move to Step 1: Deposit refund
      final stepDepositBtn = find.textContaining('ยืนยันการตรวจรับของคืน');
      expect(stepDepositBtn, findsOneWidget);
      await tester.tap(stepDepositBtn);
      await tester.pumpAndSettle();

      // Verify deposit amount
      expect(find.textContaining('฿2000'), findsWidgets);
      expect(find.textContaining('โอนคืนเงินประกัน'), findsOneWidget);
    });

    testWidgets('RentalReviewDialog allows star selection and comment submission', (
      tester,
    ) async {
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
    });
  });
}
