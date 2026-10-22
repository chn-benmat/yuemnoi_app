import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/profile/presentation/pages/account/edit_profile_screen.dart';
import 'package:frontend/features/profile/presentation/pages/legal/privacy_policy_screen.dart';
import 'package:frontend/features/profile/presentation/pages/legal/terms_of_service_screen.dart';
import 'package:frontend/features/profile/presentation/pages/account/edit_contact_screen.dart';
import 'package:frontend/features/profile/presentation/pages/account/change_password_screen.dart';

void main() {
  testWidgets('contact email cannot accept edits that the API cannot save', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditContactScreen()));
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.readOnly, isTrue);
    expect(fields.last.readOnly, isFalse);
  });

  testWidgets('password form asks only for values used by the session API', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ProfileChangePasswordScreen()),
    );
    expect(find.text('รหัสผ่านเดิม'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  for (final entry in <String, Widget>{
    'profile': const EditProfileScreen(),
    'contact': const EditContactScreen(),
    'password': const ProfileChangePasswordScreen(),
    'privacy': const PrivacyPolicyScreen(),
    'terms': const TermsOfServiceScreen(),
  }.entries) {
    testWidgets(
      '${entry.key} scrolls without overflow at narrow width and large text',
      (tester) async {
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
            home: entry.value,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -800),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'legal documents clearly show unpublished status without placeholder policy',
    (tester) async {
      for (final page in const [
        PrivacyPolicyScreen(),
        TermsOfServiceScreen(),
      ]) {
        await tester.pumpWidget(MaterialApp(home: page));
        expect(find.text('เนื้อหาอยู่ระหว่างจัดทำ'), findsOneWidget);
        expect(find.textContaining('Lorem'), findsNothing);
      }
    },
  );

  testWidgets(
    'password visibility toggle preserves validation and typed value',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ProfileChangePasswordScreen()),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'example-password',
      );
      await tester.tap(find.byTooltip('แสดงรหัสผ่าน').first);
      await tester.pump();
      final input = tester.widget<TextField>(find.byType(TextField).first);
      expect(input.obscureText, isFalse);
      expect(input.controller!.text, 'example-password');
    },
  );

  testWidgets('bio icon aligns with the first line of its hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const EditProfileScreen()),
    );
    final icon = find.byIcon(Icons.info_outline_rounded);
    final hint = find.text('เขียนอะไรสักอย่างเกี่ยวกับตัวคุณ...');
    expect(
      (tester.getCenter(icon).dy - tester.getCenter(hint).dy).abs(),
      lessThan(1),
    );
  });
}
