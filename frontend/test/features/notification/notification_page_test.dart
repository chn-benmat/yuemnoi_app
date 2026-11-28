import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

void main() {
  testWidgets('asks guests to sign in before loading notifications', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationPage()));

    expect(find.text('การแจ้งเตือน'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบเพื่อดูการแจ้งเตือน'), findsOneWidget);
  });
}
