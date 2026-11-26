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

  setUp(() async {
    installed = [];
    opened = [];
    lookupCount = 0;
    launchSucceeds = true;
    SharedPreferences.setMockInitialValues({});
    await RentalPickupPaymentModal.clearSavedStep(itemId: 930);
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

  Future<void> openPickup(
    WidgetTester tester, {
    String paymentMethod = 'promptpay',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => RentalPickupPaymentModal.show(
                context,
                itemId: 930,
                itemTitle: 'Sony A7 IV',
                totalPrice: 1500,
                paymentMethod: paymentMethod,
              ),
              child: const Text('Open pickup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open pickup'));
    await tester.pumpAndSettle();
  }

  Future<void> goToPayment(WidgetTester tester) async {
    await openPickup(tester);
    await tester.tap(find.text('ไปชำระเงิน'));
    await tester.pumpAndSettle();
  }

  final payButton = find.widgetWithText(ElevatedButton, 'ชำระเงิน');

  Future<void> tapPay(WidgetTester tester) async {
    await tester.tap(payButton);
    await tester.pumpAndSettle();
  }

  testWidgets('opens a single supported payment app directly', (tester) async {
    installed = [wallet, 'com.example.unrelated'];
    await goToPayment(tester);
    expect(lookupCount, 0);
    expect(opened, isEmpty);

    await tapPay(tester);

    expect(opened, [wallet]);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
    expect(find.text('ฉันโอนเงินเรียบร้อยแล้ว'), findsNothing);
  });

  testWidgets('shows the installed apps and opens only the selection', (
    tester,
  ) async {
    installed = [bank, wallet, 'com.example.unrelated'];
    await goToPayment(tester);
    await tapPay(tester);

    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsOneWidget);
    expect(find.text('K PLUS'), findsOneWidget);
    expect(find.text('TrueMoney'), findsOneWidget);
    expect(find.text('SCB EASY'), findsNothing);
    await tester.tap(find.text('K PLUS'));
    await tester.pumpAndSettle();
    expect(opened, [bank]);
    expect(payButton.hitTestable(), findsOneWidget);
    expect(
      find.textContaining('ระบบจะแสดงรหัสส่งมอบเมื่อผู้ปล่อยเช่ายืนยัน'),
      findsNothing,
    );
    await tester.tap(find.text('ย้อนกลับไปตรวจสภาพ'));
    await tester.pumpAndSettle();
    expect(find.text('ไปชำระเงิน'), findsOneWidget);
  });

  testWidgets('reopening pickup restores payment without launching an app', (
    tester,
  ) async {
    installed = [wallet];
    await goToPayment(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open pickup'));
    await tester.pumpAndSettle();

    expect(lookupCount, 0);
    expect(opened, isEmpty);
    expect(payButton.hitTestable(), findsOneWidget);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
  });

  testWidgets('back closes the app picker and allows payment again', (
    tester,
  ) async {
    installed = [bank, wallet];
    await goToPayment(tester);
    await tapPay(tester);

    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsOneWidget);
    expect(find.text('K PLUS'), findsOneWidget);
    expect(find.text('TrueMoney'), findsOneWidget);
    expect(find.text('ย้อนกลับไปตรวจสภาพ').hitTestable(), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
    expect(payButton.hitTestable(), findsOneWidget);
    expect(find.text('ย้อนกลับไปตรวจสภาพ'), findsOneWidget);
    await tapPay(tester);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsOneWidget);
  });

  testWidgets('tapping outside the app picker keeps the payment step', (
    tester,
  ) async {
    installed = [bank, wallet];
    await goToPayment(tester);
    await tapPay(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('เลือกแอปสำหรับสแกนจ่าย'), findsNothing);
    expect(payButton.hitTestable(), findsOneWidget);
    expect(await RentalPickupPaymentModal.getSavedStep(itemId: 930), 1);
  });

  testWidgets('keeps payment instructions visible without a supported app', (
    tester,
  ) async {
    await goToPayment(tester);
    await tapPay(tester);

    expect(opened, isEmpty);
    expect(find.text('ไม่พบแอปชำระเงินที่รองรับบนเครื่องนี้'), findsOneWidget);
    expect(find.text('ฉันโอนเงินเรียบร้อยแล้ว'), findsNothing);
  });

  testWidgets('pay button retries a failed app launch', (tester) async {
    installed = [bank];
    launchSucceeds = false;
    await goToPayment(tester);
    await tapPay(tester);
    expect(opened, [bank]);
    expect(find.textContaining('เปิดแอปที่เลือกไม่ได้'), findsOneWidget);

    launchSucceeds = true;
    await tapPay(tester);
    expect(opened, [bank, bank]);
    expect(find.textContaining('เปิดแอปที่เลือกไม่ได้'), findsNothing);
  });

  testWidgets('cash inspection stays on pickup while waiting for the owner', (
    tester,
  ) async {
    installed = [bank];
    await openPickup(tester, paymentMethod: 'cash');

    expect(find.text('ไปชำระเงิน'), findsNothing);
    expect(find.text('2. ชำระเงิน'), findsNothing);
    expect(find.text('ตรวจรับอุปกรณ์'), findsOneWidget);
    expect(find.textContaining('ชำระเงินสดจำนวน ฿1500'), findsOneWidget);
    await tester.tap(find.text('ตรวจสอบเรียบร้อย'));
    await tester.pumpAndSettle();

    expect(lookupCount, 0);
    expect(opened, isEmpty);
    expect(payButton, findsNothing);
    expect(find.text('ยอดชำระสุทธิ'), findsNothing);
    expect(find.textContaining('ชำระเงินสดจำนวน ฿1500'), findsOneWidget);
    expect(
      find.text('รอผู้ปล่อยเช่ายืนยันว่าได้รับเงินเพื่อเริ่มการเช่า'),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open pickup'));
    await tester.pumpAndSettle();
    expect(
      find.text('รอผู้ปล่อยเช่ายืนยันว่าได้รับเงินเพื่อเริ่มการเช่า'),
      findsOneWidget,
    );
    expect(find.text('ไปชำระเงิน'), findsNothing);
  });
}
