import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/presentation/pages/legal/privacy_policy_screen.dart';
import 'package:frontend/features/profile/presentation/pages/legal/terms_of_service_screen.dart';

void main() {
  testWidgets(
    'privacy policy explains data use and scrolls to account deletion and support',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const PrivacyPolicyScreen(),
        ),
      );

      expect(find.text('นโยบายความเป็นส่วนตัว').hitTestable(), findsWidgets);
      expect(find.textContaining('ข้อมูลที่เราเก็บ'), findsOneWidget);
      expect(find.text('เนื้อหาอยู่ระหว่างจัดทำ'), findsNothing);

      final deletion = find.textContaining('กู้คืนบัญชีได้ภายใน 30 วัน');
      await tester.ensureVisible(deletion);
      await tester.pumpAndSettle();
      expect(deletion.hitTestable(), findsOneWidget);

      final support = find.text('yuemnoi.app@gmail.com');
      await tester.ensureVisible(support);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(support)
            .overlaps(tester.getRect(find.byType(SingleChildScrollView))),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('terms starts with the first clause and scrolls to contact', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TermsOfServiceScreen()));
    expect(find.text('ฉบับร่าง · ยังไม่ประกาศใช้'), findsNothing);
    expect(
      find.text(
        'เอกสารฉบับนี้อยู่ระหว่างตรวจทานและยังไม่มีวันที่มีผลบังคับใช้',
      ),
      findsNothing,
    );
    expect(
      find.text('1. บริการและบทบาทของยืมหน่อย').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('เนื้อหาอยู่ระหว่างจัดทำ'), findsNothing);
    expect(find.textContaining('ค่าเช่าและการชำระเงิน'), findsOneWidget);
    expect(find.textContaining('การส่งคืนและความเสียหาย'), findsOneWidget);

    final contact = find.textContaining('ข้อร้องเรียนและการติดต่อ');
    await tester.ensureVisible(contact);
    await tester.pumpAndSettle();
    expect(contact.hitTestable(), findsOneWidget);
  });
}
