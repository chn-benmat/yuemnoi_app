import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/presentation/widgets/ai_summary_bottom_sheet.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';

void main() {
  group('AISummaryBottomSheet', () {
    testWidgets(
      'renders search query, activity timeline, and reference sources',
      (tester) async {
        const messageWithSources = ChatMessage(
          id: 'assistant-summary-1',
          role: ChatMessageRole.assistant,
          content: 'เปรียบเทียบกล้องสองรุ่นเรียบร้อยแล้วค่ะ',
          userQuery: 'เปรียบเทียบกล้อง A7 IV กับ FX3',
          responseDuration: Duration(seconds: 7),
          searchQuery: 'Sony A7 IV vs Sony FX3 specs comparison',
          activities: [
            'วิเคราะห์คำถามและเจตนาของผู้ใช้',
            'ค้นหาอุปกรณ์ในคลังระบบ Yuemnoi',
            'ค้นหาข้อมูลและสเปกจาก Google ("Sony A7 IV vs Sony FX3 specs comparison")',
            'ตรวจสอบความถูกต้องของสเปกและตัดข้อมูลโฆษณา',
            'เรียบเรียงผลการเปรียบเทียบและสรุปคำแนะนำ',
          ],
          searchSources: [
            SearchSource(
              title: 'Sony A7 IV vs FX3: Full Review & In-depth Specs',
              url: 'https://dpreview.com/reviews/sony-a7iv-vs-fx3',
              domain: 'dpreview.com',
              snippet: 'Detailed side by side sensor and video comparison.',
            ),
            SearchSource(
              title: 'Sony Official Thailand - Camera Specifications',
              url: 'https://sony.co.th/camera-specs',
              domain: 'sony.co.th',
              snippet: 'Official specifications and dimensions.',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      AISummaryBottomSheet.show(context, messageWithSources),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        );

        // แตะเปิด Bottom Sheet
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // ตรวจสอบ Header
        expect(find.byType(AISummaryBottomSheet), findsOneWidget);
        expect(find.textContaining('7 วินาที'), findsOneWidget);

        // ตรวจสอบ Web Search Query Card
        expect(find.text('คำค้นที่ใช้'), findsOneWidget);
        expect(
          find.text('Sony A7 IV vs Sony FX3 specs comparison'),
          findsOneWidget,
        );

        // ตรวจสอบขั้นตอนการทำงาน (Timeline)
        expect(find.text('การทำงานที่ได้รับ'), findsOneWidget);
        expect(find.text('วิเคราะห์คำถามและเจตนาของผู้ใช้'), findsOneWidget);
        expect(find.text('ค้นหาอุปกรณ์ในคลังระบบ Yuemnoi'), findsOneWidget);
        expect(
          find.text('ตรวจสอบความถูกต้องของสเปกและตัดข้อมูลโฆษณา'),
          findsOneWidget,
        );

        // ตรวจสอบแหล่งอ้างอิง (Sources)
        expect(find.text('แหล่งข้อมูลอ้างอิง (2)'), findsOneWidget);
        expect(find.text('dpreview.com'), findsOneWidget);
        expect(
          find.text('Sony A7 IV vs FX3: Full Review & In-depth Specs'),
          findsOneWidget,
        );
        expect(
          find.text('Detailed side by side sensor and video comparison.'),
          findsOneWidget,
        );
        expect(find.text('sony.co.th'), findsOneWidget);

        // ปิด Sheet โดยแตะปุ่ม X
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(AISummaryBottomSheet), findsNothing);
      },
    );

    testWidgets(
      'tapping status header in ChatMessageBubble opens AISummaryBottomSheet',
      (tester) async {
        const completedMessage = ChatMessage(
          id: 'assistant-bubble-test',
          role: ChatMessageRole.assistant,
          content: 'สวัสดีค่ะ มีอะไรให้น้องยืมหน่อยช่วยไหมคะ',
          userQuery: 'สวัสดี',
          responseDuration: Duration(seconds: 3),
          activities: [
            'วิเคราะห์ข้อความของผู้ใช้',
            'เรียบเรียงคำตอบและข้อความต้อนรับ',
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: completedMessage,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ตรวจสอบว่ามี Chevron และ Status Header
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
        expect(find.text('สรุปคำแนะนำ (3 วิ)'), findsOneWidget);

        // แตะที่ Status Header
        await tester.tap(
          find.byKey(
            const ValueKey(
              'chatbot-status-header-button-assistant-bubble-test',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ตรวจสอบว่า Bottom Sheet เปิดขึ้นมา
        expect(find.byType(AISummaryBottomSheet), findsOneWidget);
        expect(find.text('วิเคราะห์ข้อความของผู้ใช้'), findsOneWidget);
        expect(find.text('เรียบเรียงคำตอบและข้อความต้อนรับ'), findsOneWidget);
        // ไม่มี Search Query Card เพราะไม่ได้ค้นหา Google
        expect(find.text('Google Search (Serper.dev)'), findsNothing);
      },
    );
  });
}
