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
    expect(find.text('เริ่มต้นใช้งาน · 5 คำถาม'), findsOneWidget);
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
    final question = find.text('ลบบัญชีอย่างไร?');
    expect(question, findsOneWidget);
    await tester.scrollUntilVisible(
      question,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      allOf(
        contains('โปรไฟล์ → ศูนย์ความเป็นส่วนตัว → ลบบัญชีผู้ใช้'),
        contains('ยืนยันลบบัญชี'),
        contains('รายการเช่าที่ค้าง'),
        contains('30 วัน'),
        contains('กู้คืนบัญชี'),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
