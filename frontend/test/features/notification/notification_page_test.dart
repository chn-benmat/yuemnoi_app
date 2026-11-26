import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

void main() {
  testWidgets('shows the maintenance state without account or data setup', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationPage()));

    expect(find.text('การแจ้งเตือน'), findsOneWidget);
    expect(find.text('ระบบแจ้งเตือนกำลังปรับปรุง'), findsOneWidget);
  });
}
