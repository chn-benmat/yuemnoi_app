import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/features/profile/presentation/pages/account/change_account_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('privacy center contains privacy groups without notifications', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChangeAccountScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ศูนย์ความเป็นส่วนตัว'), findsOneWidget);
    expect(find.text('บัญชีและความปลอดภัย'), findsOneWidget);
    expect(find.text('ความเป็นส่วนตัวและการบล็อก'), findsOneWidget);
    expect(find.text('อุปกรณ์และการจัดการบัญชี'), findsOneWidget);
    expect(find.text('ปิดการแจ้งเตือนทั้งหมดชั่วคราว'), findsNothing);
  });

  testWidgets('notification settings contain only notification controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChangeAccountScreen(notificationsOnly: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('ปิดการแจ้งเตือนทั้งหมดชั่วคราว'), findsOneWidget);
    expect(
      find.text('แจ้งเตือนเมื่อเข้าสู่ระบบจากอุปกรณ์ใหม่'),
      findsOneWidget,
    );
    expect(find.text('บัญชีและความปลอดภัย'), findsNothing);
    expect(find.text('ความเป็นส่วนตัวและการบล็อก'), findsNothing);
    expect(find.text('อุปกรณ์และการจัดการบัญชี'), findsNothing);
  });
}
