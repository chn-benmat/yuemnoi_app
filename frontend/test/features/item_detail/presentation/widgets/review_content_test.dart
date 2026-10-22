import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/presentation/widgets/review_content.dart';

void main() {
  testWidgets('separates saved highlights and wraps on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(36),
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: const ReviewContent(
                description:
                    'ดีมาก\nจุดที่ประทับใจ: 📦 สภาพสินค้าดีเยี่ยม, ⏰ ส่งมอบตรงเวลา, 💬 ตอบแชตไว สื่อสารดี, 🤝 เป็นกันเอง ให้คำแนะนำดี',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('ดีมาก'), findsOneWidget);
    expect(find.text('จุดที่ประทับใจ'), findsOneWidget);
    expect(find.text('📦 สภาพสินค้าดีเยี่ยม'), findsOneWidget);
    expect(find.text('🤝 เป็นกันเอง ให้คำแนะนำดี'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps ordinary review text intact', (tester) async {
    const text = 'สะดวก, ใช้ง่าย\nชอบมาก';
    await tester.pumpWidget(
      const MaterialApp(home: ReviewContent(description: text)),
    );
    expect(find.text(text), findsOneWidget);
    expect(find.text('จุดที่ประทับใจ'), findsNothing);
  });
}
