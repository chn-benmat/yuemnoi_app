import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chatbot_composer.dart';

void main() {
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
