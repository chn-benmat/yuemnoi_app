import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/app_popup.dart';

void main() {
  testWidgets('popup survives caller pop and closes without popping home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () {
                          showAppPopup(
                            context,
                            content: const Text('บันทึกไม่สำเร็จ'),
                          );
                          Navigator.of(context).pop();
                        },
                        child: const Text('บันทึก'),
                      ),
                    ),
                  ),
                ),
                child: const Text('หน้าหลัก'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('หน้าหลัก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    final popup = find.widgetWithText(Dialog, 'บันทึกไม่สำเร็จ');
    expect(popup, findsOneWidget);
    await tester.tap(find.descendant(of: popup, matching: find.text('ยืนยัน')));
    await tester.pumpAndSettle();
    expect(find.text('หน้าหลัก'), findsOneWidget);
    expect(popup, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending popup is ignored after navigator disposal', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    showAppPopup(pageContext, content: const Text('บันทึกไม่สำเร็จ'));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
