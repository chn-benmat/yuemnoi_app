import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_pickup_payment_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('yuemnoi/promptpay_apps');
  const bank = 'com.kasikorn.retail.mbanking.wap';
  const wallet = 'th.co.truemoney.wallet';
  late List<String> installed;
  late List<String> opened;
  late int lookupCount;
  late bool launchSucceeds;

  setUp(() {
    installed = [];
    opened = [];
    lookupCount = 0;
    launchSucceeds = true;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'installedApps':
              lookupCount++;
              return installed;
            case 'openApp':
              opened.add(call.arguments as String);
              return launchSucceeds;
          }
          throw MissingPluginException(call.method);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> goToPayment(
    WidgetTester tester, {
    String paymentMethod = 'promptpay',
    bool resumePayment = false,
  }) async {
    await RentalPickupPaymentModal.clearSavedStep(itemId: 930);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RentalPickupPaymentModal(
            key: ValueKey(resumePayment),
            itemId: 930,
            itemTitle: 'Sony A7 IV',
            totalPrice: 1500,
            paymentMethod: paymentMethod,
            initialStep: resumePayment ? 1 : null,
            openPaymentAppOnShow: resumePayment,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!resumePayment) {
      await tester.tap(find.text('ชำระเงิน'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('opens a single supported payment app directly', (tester) async {
    installed = [wallet, 'com.example.unrelated'];
    await goToPayment(tester);

    expect(opened, [wallet]);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
    expect(find.text('ฉันโอนเงินเรียบร้อยแล้ว'), findsNothing);
  });

  testWidgets('shows the installed apps and opens only the selection', (
    tester,
  ) async {
    installed = [bank, wallet, 'com.example.unrelated'];
    await goToPayment(tester);

    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsOneWidget);
    expect(find.text('K PLUS'), findsOneWidget);
    expect(find.text('TrueMoney'), findsOneWidget);
    expect(find.text('SCB EASY'), findsNothing);
    await tester.tap(find.text('K PLUS'));
    await tester.pumpAndSettle();
    expect(opened, [bank]);
    expect(find.widgetWithText(ElevatedButton, 'ชำระเงิน'), findsNothing);
    expect(
      find.textContaining('ระบบจะแสดงรหัสส่งมอบเมื่อผู้ปล่อยเช่ายืนยัน'),
      findsNothing,
    );
    await tester.tap(find.text('ย้อนกลับไปตรวจสภาพ'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ElevatedButton, 'ชำระเงิน'), findsOneWidget);
  });

  testWidgets('resuming payment opens the only installed app once', (
    tester,
  ) async {
    installed = [wallet];
    await goToPayment(tester, resumePayment: true);

    expect(lookupCount, 1);
    expect(opened, [wallet]);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
  });

  testWidgets('dismissing the resumed app picker returns to inspection', (
    tester,
  ) async {
    installed = [bank, wallet];
    await goToPayment(tester, resumePayment: true);

    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsOneWidget);
    expect(find.text('K PLUS'), findsOneWidget);
    expect(find.text('TrueMoney'), findsOneWidget);
    expect(find.text('ย้อนกลับไปตรวจสภาพ').hitTestable(), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'ชำระเงิน'), findsOneWidget);
  });

  testWidgets('tapping outside the app picker returns to inspection', (
    tester,
  ) async {
    installed = [bank, wallet];
    await goToPayment(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'ชำระเงิน'), findsOneWidget);
    expect(await RentalPickupPaymentModal.getSavedStep(itemId: 930), 0);
  });

  testWidgets('keeps payment instructions visible without a supported app', (
    tester,
  ) async {
    await goToPayment(tester);

    expect(opened, isEmpty);
    expect(find.text('ไม่พบแอปชำระเงินที่รองรับบนเครื่องนี้'), findsOneWidget);
    expect(find.text('ฉันโอนเงินเรียบร้อยแล้ว'), findsNothing);
  });

  testWidgets('reopening payment retries a failed app launch', (tester) async {
    installed = [bank];
    launchSucceeds = false;
    await goToPayment(tester);
    expect(opened, [bank]);
    expect(find.textContaining('เปิดแอปที่เลือกไม่ได้'), findsOneWidget);

    launchSucceeds = true;
    await goToPayment(tester, resumePayment: true);
    expect(opened, [bank, bank]);
    expect(find.textContaining('เปิดแอปที่เลือกไม่ได้'), findsNothing);
  });

  testWidgets('cash payment does not query or open other apps', (tester) async {
    installed = [bank];
    await goToPayment(tester, paymentMethod: 'cash');

    expect(lookupCount, 0);
    expect(opened, isEmpty);
    expect(
      find.text('รอผู้ปล่อยเช่ายืนยันว่าได้รับเงินเพื่อเริ่มการเช่า'),
      findsOneWidget,
    );
  });
}
