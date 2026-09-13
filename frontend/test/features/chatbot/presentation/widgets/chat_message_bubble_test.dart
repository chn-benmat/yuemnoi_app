import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';
import 'package:frontend/features/chatbot/presentation/widgets/interactive_questionnaire_card.dart';

void main() {
  group('ChatMessageBubble Streaming Markdown', () {
    testWidgets('renders styled markdown progressively even during streaming', (
      tester,
    ) async {
      const markdownContent =
          '### 🚗 รถตู้ที่แนะนำ:\n- **Toyota Alphard**: มีที่นั่ง 8 ที่นั่ง';
      const streamingMessage = ChatMessage(
        id: 'assistant-1',
        role: ChatMessageRole.assistant,
        content: markdownContent,
        isStreaming: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: Scaffold(
            body: ChatMessageBubble(
              message: streamingMessage,
              onRentPressed: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('🚗 รถตู้ที่แนะนำ:'), findsOneWidget);
      expect(find.textContaining('###'), findsNothing);
      expect(
        find.byKey(const ValueKey('chatbot-markdown-response-assistant-1')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: Scaffold(
            body: ChatMessageBubble(
              message: const ChatMessage(
                id: 'assistant-1',
                role: ChatMessageRole.assistant,
                content: markdownContent,
              ),
              onRentPressed: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('🚗 รถตู้ที่แนะนำ:'), findsOneWidget);
      expect(find.textContaining('###'), findsNothing);
    });

    testWidgets(
      'renders bold text without showing raw asterisks even with inner spaces',
      (tester) async {
        const markdownWithSpaces =
            '• ** ค้นหาและแนะนำอุปกรณ์ **: บอกสเปก ทริป หรือประเภทงานที่ต้องการ\n'
            '• ** เปรียบเทียบสเปกและความคุ้มค่า **: ช่วยวิเคราะห์จุดเด่น';
        const message = ChatMessage(
          id: 'assistant-bold-test',
          role: ChatMessageRole.assistant,
          content: markdownWithSpaces,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: message,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(find.textContaining('**'), findsNothing);
        expect(find.textContaining('ค้นหาและแนะนำอุปกรณ์'), findsOneWidget);
        expect(find.textContaining('เปรียบเทียบสเปกและความคุ้มค่า'), findsOneWidget);
      },
    );

    testWidgets(
      'renders plain Text widget for simple message without markdown',
      (tester) async {
        const plainContent = 'สวัสดีค่ะ ยินดีต้อนรับสู่ Yuemnoi ค่ะ';
        const message = ChatMessage(
          id: 'assistant-plain',
          role: ChatMessageRole.assistant,
          content: plainContent,
          isStreaming: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        );

        expect(find.byType(MarkdownBody), findsNothing);
        expect(find.text(plainContent), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT render RecommendedItemCard when message has unanswered questions',
      (tester) async {
        const message = ChatMessage(
          id: 'assistant-questionnaire',
          role: ChatMessageRole.assistant,
          content: 'จะแนะนำให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊',
          recommendedItems: [
            RecommendedItem(
              id: 1,
              name: 'กล้อง Canon EOS R50',
              price: 500,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'กล้องและอุปกรณ์ถ่ายภาพ',
              description: 'กล้องมิเรอร์เลส',
            ),
          ],
          questions: [
            ClarificationQuestion(
              id: 'q1',
              step: 1,
              totalSteps: 2,
              title: 'ลักษณะการใช้งานหลัก?',
              options: ['Vlog', 'ภาพนิ่ง'],
              selectedOption: null, // Unanswered!
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Guaranteed: RecommendedItemCard must NOT be rendered!
        expect(find.byType(RecommendedItemCard), findsNothing);
        expect(find.text('กล้อง Canon EOS R50'), findsNothing);
      },
    );

    testWidgets(
      'does not render AI thought or thinking duration trigger',
      (tester) async {
        const message = ChatMessage(
          id: 'assistant-thought-test',
          role: ChatMessageRole.assistant,
          content: 'คำตอบทดสอบ',
          responseDuration: Duration(seconds: 4),
          thought: 'กำลังวิเคราะห์สเปกและการใช้งานของกล้อง',
          searchSources: [
            SearchSource(
              title: 'Canon Official Spec',
              url: 'https://th.canon/eos-r50',
              domain: 'th.canon',
            ),
          ],
          searchQuery: 'Canon EOS R50 spec',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Trigger and details card must NOT be rendered
        expect(
          find.byKey(const Key('chatbot-thought-trigger-assistant-thought-test')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('chatbot-thought-details-card')),
          findsNothing,
        );
        expect(find.text('ค้นหาข้อมูลจากเว็บ 4 วินาที'), findsNothing);
        expect(find.text('ใช้ความคิด 4 วินาที'), findsNothing);
        expect(find.text('คำตอบทดสอบ'), findsOneWidget);
      },
    );

    testWidgets(
      'renders questionnaire recap card with question title and bold answer, without step badge',
      (tester) async {
        const message = ChatMessage(
          id: 'assistant-recap-test',
          role: ChatMessageRole.assistant,
          content: 'บันทึกคำตอบแล้วค่ะ',
          questions: [
            ClarificationQuestion(
              id: 'q_days',
              title: 'ทริปนี้กี่วัน / ระดับความยาก?',
              options: ['เดินวันเดียว (day hike)', 'ค้างคืน'],
              selectedOption: 'เดินวันเดียว (day hike)',
            ),
            ClarificationQuestion(
              id: 'q_weather',
              title: 'จะไปช่วงไหน/สภาพอากาศ?',
              options: ['หน้าฝน', 'หน้าหนาว'],
              selectedOption: 'หน้าฝน',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(QuestionnaireRecapCard), findsOneWidget);
        expect(find.text('ทริปนี้กี่วัน / ระดับความยาก?'), findsOneWidget);
        expect(find.text('เดินวันเดียว (day hike)'), findsOneWidget);
        expect(find.text('จะไปช่วงไหน/สภาพอากาศ?'), findsOneWidget);
        expect(find.text('หน้าฝน'), findsOneWidget);

        // Verify NO step badge or checkmark circle
        expect(find.textContaining('of 2'), findsNothing);
        expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      },
    );

    testWidgets(
      'does not render inline choice buttons inside message bubble when questions are unanswered',
      (tester) async {
        const message = ChatMessage(
          id: 'assistant-choice-test',
          role: ChatMessageRole.assistant,
          content: 'อยากให้ช่วยแนะนำแบบไหนครับ ขอเช็คบริบทก่อนสักนิด เพราะคำแนะนำจะต่างกันมาก',
          questions: [
            ClarificationQuestion(
              id: 'q_category',
              title: 'เลือกหมวดหมู่ที่ต้องการ:',
              options: ['กล้องและเลนส์', 'อุปกรณ์แคมป์ปิ้ง', 'เครื่องเสียง', 'คอมพิวเตอร์'],
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: message,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('กล้องและเลนส์'), findsNothing);
        expect(find.text('อุปกรณ์แคมป์ปิ้ง'), findsNothing);
        expect(find.text('เครื่องเสียง'), findsNothing);
        expect(find.text('คอมพิวเตอร์'), findsNothing);
      },
    );

    testWidgets(
      'renders structured comparison markdown with headings and blockquote callout correctly',
      (tester) async {
        const comparisonContent =
            'เปรียบเทียบระหว่าง PlayStation 5 และ Nintendo Switch OLED ครับ\n\n'
            '### 🎮 PlayStation 5\n'
            '- **กราฟิกและประสิทธิภาพ**: รองรับ 4K สูงสุด 120fps พร้อม Ray Tracing\n'
            '- **รูปแบบการเล่น**: ออกแบบมาสำหรับการเล่นต่อทีวีเป็นหลัก\n\n'
            '### 🕹️ Nintendo Switch OLED\n'
            '- **หน้าจอและการพกพา**: จอ OLED ขนาด 7 นิ้ว พกพาเล่นได้ทุกที่\n'
            '- **รูปแบบการเล่น**: รองรับทั้งแบบพกพาและต่อทีวี\n\n'
            '> 💡 **สรุปความคุ้มค่าและคำแนะนำ**:\n'
            '> หากต้องการกราฟิกสมจริง เล่นที่บ้าน แนะนำ PS5 แต่ถ้าเน้นพกพา แนะนำ Switch OLED ครับ\n\n'
            'คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมได้ที่การ์ดด้านล่างได้เลยครับ';

        const message = ChatMessage(
          id: 'assistant-comparison-format-test',
          role: ChatMessageRole.assistant,
          content: comparisonContent,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: message,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MarkdownBody), findsOneWidget);
        // Heading text rendered without raw markdown hash marks
        expect(find.textContaining('###'), findsNothing);
        expect(find.textContaining('PlayStation 5'), findsWidgets);
        expect(find.textContaining('Nintendo Switch OLED'), findsWidgets);
        // Blockquote text rendered without raw markdown > markers
        expect(find.textContaining('>'), findsNothing);
        expect(find.textContaining('สรุปความคุ้มค่าและคำแนะนำ'), findsOneWidget);
        expect(find.textContaining('หากต้องการกราฟิกสมจริง'), findsOneWidget);
      },
    );

    testWidgets(
      'synchronizes recommended item card title with AI answered bold model name',
      (tester) async {
        const responseContent =
            'ขอแนะนำอุปกรณ์คอมพิวเตอร์และจอภาพสำหรับใช้งานหลากหลายงานมาให้ดูนะคะ\n\n'
            '• **MacBook Air M2 13 นิ้ว**: แล็ปท็อปบางเบา ชิป Apple M2\n'
            '• **Dell UltraSharp 27 นิ้ว 4K**: จอภาพความละเอียด 4K IPS สเปกตรัมสีแม่นยำ\n\n'
            'คุณลูกค้าสามารถแตะดูรายละเอียดและกดเช่าจากรายการสินค้าด้านล่างได้เลยนะคะ';

        const message = ChatMessage(
          id: 'assistant-sync-card-title-test',
          role: ChatMessageRole.assistant,
          content: responseContent,
          recommendedItems: [
            RecommendedItem(
              id: 7,
              name: 'MacBook Air M2 13 นิ้ว',
              price: 900,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'คอมพิวเตอร์และอุปกรณ์ไอที',
              description: 'แล็ปท็อป Apple M2',
            ),
            RecommendedItem(
              id: 9,
              name: 'จอมอนิเตอร์ Dell UltraSharp 27 นิ้ว 4K',
              price: 350,
              unit: 'ชั่วโมง',
              imageUrl: '',
              status: 'available',
              category: 'คอมพิวเตอร์และอุปกรณ์ไอที',
              description: 'จอภาพ 4K',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: message,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Card 1 matches directly
        expect(find.text('MacBook Air M2 13 นิ้ว'), findsWidgets);
        // Card 2 title should display "Dell UltraSharp 27 นิ้ว 4K" matching the AI response, NOT "จอมอนิเตอร์ Dell UltraSharp 27 นิ้ว 4K"
        expect(find.text('Dell UltraSharp 27 นิ้ว 4K'), findsWidgets);
        expect(find.text('จอมอนิเตอร์ Dell UltraSharp 27 นิ้ว 4K'), findsNothing);
      },
    );

    testWidgets(
      'synchronizes recommended item card titles with AI extracted bold model names (e.g. PlayStation 5 and Nintendo Switch OLED)',
      (tester) async {
        const responseContent =
            'ทั้งสองรุ่นตอบโจทย์การใช้งานคนละรูปแบบอย่างชัดเจนค่ะ:\n\n'
            '### 🎮 กราฟิกและประสิทธิภาพ\n'
            '- **PlayStation 5**: มีประสิทธิภาพประมวลผลสูงสุดสำหรับเกม AAA ภาพ 4K คมชัด\n'
            '- **Nintendo Switch OLED**: เน้นเล่นแบบ Handheld จอ OLED สีสด เล่นเกมอินดี้สนุกค่ะ\n\n'
            '### 🚀 การพกพา\n'
            '- **Nintendo Switch OLED**: พกพาสะดวก น้ำหนักเบา เล่นได้ทั้งในบ้านและนอกบ้าน\n'
            '- **PlayStation 5**: ต้องตั้งโต๊ะเชื่อมต่อจอทีวีและเสียบปลั๊กไฟในบ้านเป็นหลักค่ะ\n\n'
            '### 👥 แนวเกมและกลุ่มผู้เล่น\n'
            '- **PlayStation 5**: เหมาะกับคอเกมตัวยง ผู้เล่นสายกราฟิก หรือแนวแข่งขัน FPS/RPG\n'
            '- **Nintendo Switch OLED**: เหมาะกับครอบครัว เล่นปาร์ตี้กับเพื่อน และเกมแนวผจญภัยค่ะ\n\n'
            '💡 **คำแนะนำในการเลือก**:\n'
            '- **PlayStation 5**: เหมาะสำหรับคุณ หากต้องการประสบการณ์เกมระดับพรีเมียมในบ้านค่ะ\n'
            '- **Nintendo Switch OLED**: เหมาะสำหรับคุณ หากต้องการความยืดหยุ่น พกพาไปเล่นได้ทุกที่ค่ะ\n\n'
            'คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมและราคาเช่าของอุปกรณ์ได้ที่การ์ดด้านล่างได้เลยนะคะ';

        const message = ChatMessage(
          id: 'assistant-sync-card-gaming-test',
          role: ChatMessageRole.assistant,
          content: responseContent,
          recommendedItems: [
            RecommendedItem(
              id: 1,
              name: 'PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น',
              price: 450,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'เกมและอุปกรณ์เล่นเกม',
              description: 'เครื่องเกมคอนโซล',
            ),
            RecommendedItem(
              id: 2,
              name: 'Nintendo Switch OLED พร้อมจอย 4 ตัว',
              price: 350,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'เกมและอุปกรณ์เล่นเกม',
              description: 'เครื่องเล่นเกมพกพา',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatMessageBubble(
                  message: message,
                  onRentPressed: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Card 1 title displays concise model name "PlayStation 5"
        expect(find.text('PlayStation 5'), findsWidgets);
        expect(find.text('PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น'), findsNothing);

        // Card 2 title displays concise model name "Nintendo Switch OLED"
        expect(find.text('Nintendo Switch OLED'), findsWidgets);
        expect(find.text('Nintendo Switch OLED พร้อมจอย 4 ตัว'), findsNothing);
      },
    );

    testWidgets(
      'renders status summary header with duration on completed assistant response',
      (tester) async {
        const message = ChatMessage(
          id: 'assistant-complete-status',
          role: ChatMessageRole.assistant,
          content: 'คำแนะนำเรียบร้อยค่ะ',
          userQuery: 'อยากเช่ากล้อง',
          responseDuration: Duration(seconds: 6),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: message,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
        expect(find.text('สรุปคำแนะนำ (6 วิ)'), findsOneWidget);
      },
    );

    testWidgets(
      'does not render status summary header on initial greeting assistant message',
      (tester) async {
        const initialGreeting = ChatMessage(
          role: ChatMessageRole.assistant,
          content: 'สวัสดีค่ะ ฉันคือ Yuemnoi ผู้ช่วยแนะนำอุปกรณ์เช่า',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: initialGreeting,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
        expect(find.textContaining('สรุปคำแนะนำ'), findsNothing);
      },
    );

    testWidgets(
      'renders real-time status message when assistant message is streaming',
      (tester) async {
        final startTime = DateTime.now().subtract(const Duration(seconds: 4));
        final streamingMessage = ChatMessage(
          id: 'assistant-streaming-status',
          role: ChatMessageRole.assistant,
          content: 'กำลังพิมพ์คำตอบ...',
          userQuery: 'หาคอมพิวเตอร์',
          isStreaming: true,
          statusMessage: 'กำลังค้นหาอุปกรณ์ในระบบ...',
          createdAt: startTime,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Prompt'),
            home: Scaffold(
              body: ChatMessageBubble(
                message: streamingMessage,
                onRentPressed: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
        expect(find.textContaining('กำลังค้นหาอุปกรณ์ในระบบ...'), findsOneWidget);
      },
    );
  });
}

