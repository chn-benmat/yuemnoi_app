import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/profile/data/datasources/rental_management_remote_data_source.dart';
import 'package:frontend/features/profile/data/repositories/rental_management_repository_impl.dart';
import 'package:frontend/features/profile/domain/usecases/update_booking_status_usecase.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_pickup_payment_modal.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_return_modal.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_review_dialog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHandoverApiClient extends Mock implements ApiClient {}

void main() {
  group('Rental Flow Modals and Dialogs', () {
    testWidgets('lender needs a booking before setting up PromptPay', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RentalPickupPaymentModal(
              itemTitle: 'Sony A7 IV',
              totalPrice: 1500,
              initialIsOwner: true,
            ),
          ),
        ),
      );
      expect(
        find.text('ไม่พบรายการเช่าสำหรับสร้าง QR พร้อมเพย์'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets(
      'renter can return to inspection while awaiting PromptPay confirmation',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RentalPickupPaymentModal(
                itemTitle: 'Sony A7 IV',
                totalPrice: 1500,
                paymentMethod: 'promptpay',
                initialStep: 1,
              ),
            ),
          ),
        );

        expect(find.text('เปิดแอปธนาคารหรือวอลเล็ต'), findsNothing);
        expect(find.text('ฉันโอนเงินเรียบร้อยแล้ว'), findsNothing);
        expect(find.text('ย้อนกลับไปตรวจสภาพ'), findsOneWidget);
        expect(find.byIcon(Icons.qr_code_2_rounded), findsNothing);
        expect(find.textContaining('PromptPay:'), findsNothing);
      },
    );

    for (final method in ['promptpay', 'cash']) {
      testWidgets('$method starts the rental and closes the payment sheets', (
        tester,
      ) async {
        const path = '/api/rentals/501/handover-payment';
        const headers = {'Authorization': 'Bearer test-session'};
        final client = MockHandoverApiClient();
        var active = false;
        ApiResponse paymentResponse() => ApiResponse(
          statusCode: 200,
          data: {
            'status': active ? 'active' : 'confirmed',
            'payment_method': method,
            'payment_confirmed': active,
            'can_collect_payment': method == 'promptpay' && !active,
            'total_satang': 150000,
            if (method == 'promptpay' && !active) ...{
              'promptpay_qr': 'existing-lender-qr',
              'promptpay_phone': '0812345678',
            },
          },
        );
        when(
          () => client.get(path, headers: headers),
        ).thenAnswer((_) async => paymentResponse());
        when(() => client.post(path, headers: headers)).thenAnswer((_) async {
          active = true;
          return paymentResponse();
        });
        AuthSession.saveAccessToken('test-session');
        addTearDown(AuthSession.clear);
        final useCase = UpdateBookingStatusUseCase(
          RentalManagementRepositoryImpl(
            remoteDataSource: RentalManagementRemoteDataSource(
              apiClient: client,
            ),
          ),
        );
        SharedPreferences.setMockInitialValues({});
        await RentalPickupPaymentModal.clearSavedStep(bookingId: 501);
        final statuses = <String>[];
        Future<void> openSheet({required bool isOwner}) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      final status = await RentalPickupPaymentModal.show(
                        context,
                        bookingId: 501,
                        itemTitle: 'Sony A7 IV',
                        totalPrice: 1500,
                        paymentMethod: method,
                        initialIsOwner: isOwner,
                        initialStep: 1,
                        updateBookingStatusUseCase: useCase,
                      );
                      if (status != null) statuses.add(status);
                    },
                    child: const Text('Open booking'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open booking'));
          await tester.pumpAndSettle();
        }

        await openSheet(isOwner: true);
        final confirm = find.text('ยืนยันว่าได้รับเงินครบถ้วนแล้ว [฿1500]');
        expect(confirm, findsOneWidget);
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(statuses, ['active']);
        expect(find.byType(RentalPickupPaymentModal), findsNothing);
        expect(find.text('Open booking').hitTestable(), findsOneWidget);
        verify(() => client.post(path, headers: headers)).called(1);

        active = false;
        SharedPreferences.setMockInitialValues({
          'handover_progress_step_booking_501': 2,
          'handover_progress_step_booking_501_max': 2,
        });
        await openSheet(isOwner: false);
        expect(find.byType(RentalPickupPaymentModal), findsOneWidget);
        expect(find.textContaining('รหัสส่งมอบ'), findsNothing);
        expect(
          find.text('รอผู้ปล่อยเช่ายืนยันว่าได้รับเงินเพื่อเริ่มการเช่า'),
          findsOneWidget,
        );
        active = true;
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pumpAndSettle();
        expect(statuses, ['active', 'active']);
        expect(find.byType(RentalPickupPaymentModal), findsNothing);
        expect(find.text('Open booking').hitTestable(), findsOneWidget);
        expect(find.text('ชำระเงินเสร็จสิ้น'), findsNothing);
      });
    }

    testWidgets('lender saves the phone once and reuses it for another rental', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 840));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const headers = {'Authorization': 'Bearer test-session'};
      const first = '/api/rentals/610/handover-payment';
      const second = '/api/rentals/611/handover-payment';
      const third = '/api/rentals/612/handover-payment';
      const firstQr =
          '00020101021229370016A00000067701011101130066812345678530376454071999.505802TH63047EDE';
      final client = MockHandoverApiClient();
      ApiResponse payment(int satang, {String? qr, String kind = 'phone'}) =>
          ApiResponse(
            statusCode: 200,
            data: {
              'status': 'confirmed',
              'payment_method': 'promptpay',
              'payment_confirmed': false,
              'can_collect_payment': true,
              'total_satang': satang,
              if (qr != null) 'promptpay_id_type': kind,
              if (qr != null && kind == 'phone')
                'promptpay_phone': '0812345678',
              'promptpay_qr': ?qr,
            },
          );
      when(
        () => client.get(first, headers: headers),
      ).thenAnswer((_) async => payment(199950));
      when(
        () => client.get(second, headers: headers),
      ).thenAnswer((_) async => payment(35000, qr: 'qr-for-next-rental'));
      when(
        () => client.put(
          first,
          headers: headers,
          data: {'promptpay_phone': '0812345678'},
        ),
      ).thenAnswer((_) async => payment(199950, qr: firstQr));
      when(
        () => client.put(
          second,
          headers: headers,
          data: {'promptpay_national_id': '1234567890121'},
        ),
      ).thenAnswer(
        (_) async => payment(35000, qr: 'national-id-qr', kind: 'national_id'),
      );
      when(() => client.get(third, headers: headers)).thenAnswer(
        (_) async =>
            payment(40000, qr: 'next-national-id-qr', kind: 'national_id'),
      );
      AuthSession.saveAccessToken('test-session');
      addTearDown(AuthSession.clear);
      final useCase = UpdateBookingStatusUseCase(
        RentalManagementRepositoryImpl(
          remoteDataSource: RentalManagementRemoteDataSource(apiClient: client),
        ),
      );
      Future<void> showBooking(int bookingId) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RentalPickupPaymentModal(
              key: ValueKey(bookingId),
              bookingId: bookingId,
              itemTitle: 'Sony A7 IV',
              totalPrice: 10,
              initialIsOwner: true,
              updateBookingStatusUseCase: useCase,
            ),
          ),
        ),
      );

      await showBooking(610);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      final confirmButton = find.widgetWithText(
        ElevatedButton,
        'ยืนยันว่าได้รับเงินครบถ้วนแล้ว [฿1999.50]',
      );
      expect(confirmButton, findsNothing);
      final saveButton = find.widgetWithText(
        ElevatedButton,
        'บันทึกเบอร์และสร้าง QR',
      );
      expect(saveButton, findsOneWidget);
      final saveStyle = tester.widget<ElevatedButton>(saveButton).style!;
      final saveSize = tester.getSize(saveButton);
      await tester.enterText(find.byType(TextFormField), '081234');
      await tester.tap(find.text('บันทึกเบอร์และสร้าง QR'));
      await tester.pumpAndSettle();
      expect(
        find.text('กรุณากรอกเบอร์มือถือพร้อมเพย์ 10 หลัก'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), '0812345678');
      await tester.tap(find.text('บันทึกเบอร์และสร้าง QR'));
      await tester.pumpAndSettle();
      verify(
        () => client.put(
          first,
          headers: headers,
          data: {'promptpay_phone': '0812345678'},
        ),
      ).called(1);
      expect(find.byType(QrImageView), findsOneWidget);
      final confirm = tester.widget<ElevatedButton>(confirmButton);
      expect(confirm.onPressed, isNotNull);
      expect(find.byType(TextFormField), findsNothing);
      expect(saveButton, findsNothing);
      expect(tester.getSize(confirmButton), saveSize);
      expect(
        confirm.style!.backgroundColor!.resolve({}),
        saveStyle.backgroundColor!.resolve({}),
      );
      expect(confirm.style!.shape!.resolve({}), saveStyle.shape!.resolve({}));

      await tester.tap(find.text('เปลี่ยนเบอร์พร้อมเพย์'));
      await tester.pumpAndSettle();
      expect(saveButton, findsOneWidget);
      expect(confirmButton, findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      await tester.tap(find.text('ใช้เบอร์เดิม'));
      await tester.pumpAndSettle();
      expect(confirmButton, findsOneWidget);

      await showBooking(611);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('฿350'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);

      await tester.tap(find.text('เปลี่ยนเบอร์พร้อมเพย์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เลขบัตรประชาชน'));
      await tester.pumpAndSettle();
      expect(find.text('เลขบัตรประชาชนที่ผูกพร้อมเพย์'), findsOneWidget);
      final field = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(field).controller!.text, isEmpty);
      await tester.enterText(field, '1234');
      await tester.tap(find.text('บันทึกเลขบัตรและสร้าง QR'));
      await tester.pumpAndSettle();
      expect(find.text('กรุณากรอกเลขบัตรประชาชน 13 หลัก'), findsOneWidget);
      await tester.enterText(field, '1234567890121');
      await tester.tap(find.text('บันทึกเลขบัตรและสร้าง QR'));
      await tester.pumpAndSettle();
      verify(
        () => client.put(
          second,
          headers: headers,
          data: {'promptpay_national_id': '1234567890121'},
        ),
      ).called(1);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(field, findsNothing);
      await showBooking(612);
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('฿400'), findsOneWidget);
      await tester.tap(find.text('เปลี่ยนเลขพร้อมเพย์'));
      await tester.pumpAndSettle();
      expect(find.text('เลขบัตรประชาชนที่ผูกพร้อมเพย์'), findsOneWidget);
      expect(tester.widget<TextFormField>(field).controller!.text, isEmpty);
    });

    testWidgets(
      'Renter inspection exposes evidence-based cancellation before payment',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RentalPickupPaymentModal(
                itemTitle: 'Sony A7 IV',
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
        expect(find.text('ไปชำระเงิน'), findsOneWidget);
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
