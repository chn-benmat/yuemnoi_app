import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chatbot_composer.dart';

void main() {
  group('multiline keyboard input', () {
    late TextEditingController controller;
    late FocusNode focus;
    late List<String> submitted;
    late bool registeredTearDown;

    setUp(() {
      controller = TextEditingController();
      focus = FocusNode();
      submitted = [];
      registeredTearDown = false;
    });

    Future<void> pumpComposer(
      WidgetTester tester, {
      bool isSending = false,
    }) async {
      if (!registeredTearDown) {
        registeredTearDown = true;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          focus.dispose();
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatbotComposer(
              controller: controller,
              focusNode: focus,
              isSending: isSending,
              onSend: () => submitted.add(controller.text),
            ),
          ),
        ),
      );
    }

    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      testWidgets('${key.keyLabel} does not submit from a physical keyboard', (
        tester,
      ) async {
        await pumpComposer(tester);
        await tester.enterText(find.byType(TextField), 'สวัสดี');
        await tester.pump();

        await tester.sendKeyEvent(key);

        expect(submitted, isEmpty);
      });
    }

    testWidgets(
      'soft keyboard keeps newlines until the send button is tapped',
      (tester) async {
        await pumpComposer(tester);
        await tester.enterText(find.byType(TextField), 'สวัสดี');
        await tester.pump();
        final initialHeight = tester.getSize(find.byType(TextField)).height;

        await tester.testTextInput.receiveAction(TextInputAction.newline);
        expect(submitted, isEmpty);
        const message = 'สวัสดี\nอยากเช่ากล้อง\nและเลนส์';
        await tester.enterText(find.byType(TextField), message);
        await tester.pump();
        expect(
          tester.getSize(find.byType(TextField)).height,
          greaterThan(initialHeight),
        );
        await tester.tap(find.byKey(const Key('chatbot-send-button')));

        expect(submitted, [message]);
      },
    );

    testWidgets('holding Enter never submits a draft', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'สวัสดี');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);

      expect(submitted, isEmpty);
    });

    testWidgets('Shift+Enter stays available for multiline input', (
      tester,
    ) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'บรรทัดแรก');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      const multilineText = 'บรรทัดแรก\nบรรทัดที่สอง';
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: multilineText,
          selection: TextSelection.collapsed(offset: multilineText.length),
        ),
      );

      expect(submitted, isEmpty);
      expect(controller.text, multilineText);
    });

    testWidgets('Enter does not submit while the IME is composing', (
      tester,
    ) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'สวัสดี');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'สวัสดี',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 0, end: 6),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(submitted, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'สวัสดี',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(submitted, isEmpty);
    });

    testWidgets('Enter does not send whitespace or send while busy', (
      tester,
    ) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), '  \n  ');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      expect(submitted, isEmpty);

      controller.text = 'สวัสดี';
      await pumpComposer(tester, isSending: true);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(submitted, isEmpty);
    });
  });

  testWidgets('preserves and submits a detailed multi-item rental request', (
    tester,
  ) async {
    const request =
        'เราจะพาเพื่อนไปแคมป์ครั้งแรกกันสี่คน เป็นทริปสองวันหนึ่งคืน '
        'อยากให้นอนสบายเพราะมีเพื่อนที่ไม่เคยกางเต็นท์มาก่อน '
        'ตอนกลางวันจะถ่ายรูปและทำคลิปสั้นไว้ลงเพจ ตอนเย็นอยากเปิดเพลงเบาๆ '
        'และเล่นเกมด้วยกัน ไม่ต้องการเครื่องเสียงใหญ่เพราะกลัวรบกวนคนอื่น '
        'ช่วยเลือกของที่มีให้เช่าจริง บอกข้อดีข้อเสียของแต่ละอย่างและอย่าแนะนำของที่ไม่พร้อมให้เช่า '
        'เราสนใจเต็นท์ Coleman กล้อง Canon R50 ลำโพง JBL และ Nintendo Switch '
        'ถ้าของบางอย่างแพงเกินงบช่วยเสนอทางเลือกด้วย งบรวมทั้งทริปไม่เกิน 4000 บาท '
        'ต้องรวมค่าเช่าสองวันทุกชิ้น ขอราคาแยกแต่ละชิ้นและยอดรวม '
        'และช่วยบอกด้วยว่ารับของที่เชียงใหม่ได้ไหม';
    final controller = TextEditingController();
    final focus = FocusNode();
    String? submitted;
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatbotComposer(
              controller: controller,
              focusNode: focus,
              isSending: false,
              onSend: () => submitted = controller.text,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('chatbot-message-field')),
      request,
    );
    await tester.pump();
    expect(controller.text, request);
    await tester.tap(find.byKey(const Key('chatbot-send-button')));
    expect(submitted, request);
    expect(tester.takeException(), isNull);
  });
}
