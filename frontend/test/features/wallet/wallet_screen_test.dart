import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/wallet/presentation/bloc/wallet_cubit.dart';
import 'package:frontend/features/wallet/presentation/pages/wallet.dart';
import 'package:frontend/features/wallet/presentation/widgets/wallet_custom_amount_bottom_sheet.dart';
import 'package:frontend/features/wallet/presentation/widgets/wallet_filter_bottom_sheet.dart';
import 'package:frontend/features/wallet/presentation/widgets/wallet_summary_bottom_sheet.dart';

void main() {
  testWidgets(
    'WalletScreen renders balance, tabs, preset buttons, and transaction history',
    (WidgetTester tester) async {
      final cubit = WalletCubit();

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<WalletCubit>.value(
            value: cubit,
            child: const WalletScreen(),
          ),
        ),
      );
      await tester.pump();

      // Verify Title & Balance Card
      expect(find.text('เงินในบัญชี'), findsOneWidget);
      expect(find.text('กระเป๋าเงินของคุณ'), findsOneWidget);
      expect(find.text('1,200.00฿'), findsOneWidget);

      // Verify Tabs
      expect(find.text('เติมเงิน'), findsOneWidget);
      expect(find.text('ประวัติการเติมเงิน'), findsOneWidget);

      // Verify Amount buttons with comma separators
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('2,500'), findsOneWidget);
      expect(find.text('5,000'), findsOneWidget);
      expect(find.text('10,000'), findsOneWidget);
      expect(find.text('50,000'), findsOneWidget);
      expect(find.text('ระบุจำนวนเงิน'), findsOneWidget);

      // Switch to history tab
      await tester.tap(find.text('ประวัติการเติมเงิน'));
      await tester.pumpAndSettle();

      // Verify transaction history item
      expect(find.text('โอนเข้าบัญชี'), findsOneWidget);
      expect(find.text('+ 1,200.00'), findsOneWidget);

      cubit.close();
    },
  );

  testWidgets('WalletSummaryBottomSheet formats 50000 with comma 50,000 บาท', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalletSummaryBottomSheet(amount: 50000, onConfirm: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('สรุปยอดการเติมเงิน'), findsOneWidget);
    expect(find.text('จำนวนที่เข้าบัญชี'), findsOneWidget);
    expect(
      find.text('50,000 บาท'),
      findsNWidgets(2),
    ); // Both entries formatted with comma
  });

  testWidgets(
    'WalletCustomAmountBottomSheet keypad, commas, and quick add works',
    (WidgetTester tester) async {
      double? confirmedAmount;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletCustomAmountBottomSheet(
              onAmountConfirmed: (val) {
                confirmedAmount = val;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ระบุจำนวนเงินที่ต้องการเติม'), findsOneWidget);

      // Tap keypad digits: 2, 5, 0
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('0'));
      await tester.pump();

      expect(find.text('250'), findsOneWidget);

      // Tap Quick Add +1,000 (with comma)
      await tester.tap(find.text('+1,000'));
      await tester.pump();

      // 250 + 1000 = 1250 -> formatted with comma '1,250'
      expect(find.text('1,250'), findsOneWidget);

      // Tap Submit
      await tester.tap(find.text('ดำเนินการต่อ (1,250 บาท)'));
      await tester.pump();

      expect(confirmedAmount, 1250.0);
    },
  );

  testWidgets('WalletFilterBottomSheet allows selection and apply', (
    WidgetTester tester,
  ) async {
    WalletFilterOptions? applied;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalletFilterBottomSheet(
            currentOptions: const WalletFilterOptions(),
            onApply: (opts) {
              applied = opts;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('กรองประวัติการเติมเงิน'), findsOneWidget);
    expect(find.text('ช่วงเวลา'), findsOneWidget);
    expect(find.text('ช่วงยอดเงิน'), findsOneWidget);
    expect(find.text('เรียงตาม'), findsOneWidget);

    // Select "วันนี้" and "1,000 - 5,000 ฿"
    await tester.tap(find.text('วันนี้'));
    await tester.pump();
    await tester.tap(find.text('1,000 - 5,000 ฿'));
    await tester.pump();

    // Tap Apply
    await tester.tap(find.text('ใช้ตัวกรอง'));
    await tester.pump();

    expect(applied?.period, WalletFilterPeriod.today);
    expect(applied?.amountRange, WalletFilterAmountRange.from1000To5000);
  });
}
