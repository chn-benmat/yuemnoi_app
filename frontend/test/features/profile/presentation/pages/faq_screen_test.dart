import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/profile/presentation/pages/support/faq_screen.dart';

void main() {
  testWidgets('FAQ opens one answer at a time and can collapse it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const FaqScreen()),
    );
    expect(find.byType(SelectableText), findsOneWidget);
    final question = find.text('การลงทะเบียนและการยืนยันตัวตน');
    await tester.ensureVisible(question);
    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('Google'),
    );
    await tester.ensureVisible(question);
    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('FAQ remains readable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.8)),
          child: child!,
        ),
        home: const FaqScreen(),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('ข้อกำหนดสำหรับผู้เช่า (Renter)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('ข้อกำหนดสำหรับผู้เช่า (Renter)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
