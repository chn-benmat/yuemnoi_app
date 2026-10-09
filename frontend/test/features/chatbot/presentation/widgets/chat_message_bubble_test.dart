import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chatbot_design.dart';
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

    testWidgets('renders valid bold Markdown without rewriting text', (
      tester,
    ) async {
      const markdownWithSpaces =
          '- **ค้นหาและแนะนำอุปกรณ์**: บอกสเปก ทริป หรือประเภทงานที่ต้องการ\n'
          '- **เปรียบเทียบสเปกและความคุ้มค่า**: ช่วยวิเคราะห์จุดเด่น';
      const message = ChatMessage(
        id: 'assistant-bold-test',
        role: ChatMessageRole.assistant,
        content: markdownWithSpaces,
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

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('ค้นหาและแนะนำอุปกรณ์'), findsOneWidget);
      expect(
        find.textContaining('เปรียบเทียบสเปกและความคุ้มค่า'),
        findsOneWidget,
      );
    });

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
          content:
              'จะแนะนำให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊',
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

    testWidgets('does not render AI thought or thinking duration trigger', (
      tester,
    ) async {
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
    });

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
          content:
              'อยากให้ช่วยแนะนำแบบไหนครับ ขอเช็คบริบทก่อนสักนิด เพราะคำแนะนำจะต่างกันมาก',
          questions: [
            ClarificationQuestion(
              id: 'q_category',
              title: 'เลือกหมวดหมู่ที่ต้องการ:',
              options: [
                'กล้องและเลนส์',
                'อุปกรณ์แคมป์ปิ้ง',
                'เครื่องเสียง',
                'คอมพิวเตอร์',
              ],
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
              body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
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
        expect(
          find.descendant(
            of: find.byType(MarkdownBody),
            matching: find.textContaining('>'),
          ),
          findsNothing,
        );
        expect(
          find.textContaining('สรุปความคุ้มค่าและคำแนะนำ'),
          findsOneWidget,
        );
        expect(find.textContaining('หากต้องการกราฟิกสมจริง'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps the full catalog name when an answer uses a shorter model name',
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
              body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Card 1 matches directly
        expect(find.text('MacBook Air M2 13 นิ้ว'), findsWidgets);
        // Card 2 title should display "Dell UltraSharp 27 นิ้ว 4K" matching the AI response, NOT "จอมอนิเตอร์ Dell UltraSharp 27 นิ้ว 4K"
        expect(find.textContaining('Dell UltraSharp 27 นิ้ว 4K'), findsWidgets);
        expect(
          find.text('จอมอนิเตอร์ Dell UltraSharp 27 นิ้ว 4K'),
          findsOneWidget,
        );
      },
    );

    testWidgets('keeps catalog bundle descriptions in card titles', (
      tester,
    ) async {
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
              child: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card 1 title displays concise model name "PlayStation 5"
      expect(find.textContaining('PlayStation 5'), findsWidgets);
      expect(
        find.text('PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น'),
        findsOneWidget,
      );

      // Card 2 title displays concise model name "Nintendo Switch OLED"
      expect(find.textContaining('Nintendo Switch OLED'), findsWidgets);
      expect(find.text('Nintendo Switch OLED พร้อมจอย 4 ตัว'), findsOneWidget);
    });

    testWidgets(
      'shows measured timing and a purple arrow above the avatar beside the answer',
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
              body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final summary = find.text('สรุปคำแนะนำ 6 วินาที >');
        expect(summary, findsOneWidget);
        final label = tester.widget<Text>(summary).textSpan! as TextSpan;
        expect(label.children!.last.style!.color, ChatbotDesign.primary);
        final avatar = find.byKey(
          const ValueKey('chatbot-assistant-avatar-assistant-complete-status'),
        );
        expect(tester.widget(avatar), isA<ClipOval>());
        final avatarRect = tester.getRect(avatar);
        expect(avatarRect.width, avatarRect.height);
        expect(find.text('ยืมหน่อย AI'), findsNothing);
        final answerRect = tester.getRect(find.text('คำแนะนำเรียบร้อยค่ะ'));
        expect(answerRect.top, avatarRect.top);
        expect(answerRect.left, greaterThan(avatarRect.right));
        expect(
          tester.getRect(summary).bottom,
          lessThanOrEqualTo(avatarRect.top),
        );
        expect(find.byTooltip('คัดลอกคำตอบ'), findsNothing);
        expect(find.byIcon(Icons.copy_outlined), findsNothing);
        await tester.tap(
          find.byKey(
            const ValueKey(
              'chatbot-status-header-button-assistant-complete-status',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('สรุปคำแนะนำ'), findsOneWidget);
        expect(find.textContaining('เวลาประมวลผล'), findsNothing);
      },
    );

    testWidgets(
      'allows opening the summary for a completed greeting without sources',
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
        expect(find.text('สรุปคำแนะนำ >'), findsOneWidget);
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

        expect(find.text('สรุปคำแนะนำ >'), findsNothing);
        expect(
          find.textContaining('กำลังค้นหาอุปกรณ์ในระบบ...'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows fixed completion timing without a ticking stream timer',
      (tester) async {
        const streaming = ChatMessage(
          id: 'assistant-timer-test',
          role: ChatMessageRole.assistant,
          content: 'กำลังพิมพ์คำตอบ...',
          userQuery: 'หาคอมพิวเตอร์',
          isStreaming: true,
          statusMessage: 'กำลังสรุปคำแนะนำ...',
        );
        Widget mount(ChatMessage message) => MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(message: message, onRentPressed: (_) {}),
          ),
        );
        await tester.pumpWidget(mount(streaming));
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('กำลังสรุปคำแนะนำ...'), findsOneWidget);
        expect(find.textContaining('วิ'), findsNothing);
        await tester.pumpWidget(
          mount(
            streaming.copyWith(
              isStreaming: false,
              responseDuration: const Duration(seconds: 3),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('สรุปคำแนะนำ 3 วินาที >'), findsOneWidget);
        await tester.tap(
          find.byKey(
            const ValueKey('chatbot-status-header-button-assistant-timer-test'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('เวลาประมวลผล 3 วินาที'), findsNothing);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('เวลาประมวลผล 3 วินาที'), findsNothing);
      },
    );
    testWidgets('renders all validated cards without matching names in answer text', (
      tester,
    ) async {
      const responseContent =
          'สำหรับหมวดหมู่แคมป์ปิงและกิจกรรมกลางแจ้ง น้องยืมหน่อยมีอุปกรณ์พร้อมแนะนำดังนี้นะคะ:\n\n'
          '• **เต็นท์ Coleman Instant Cabin 4 คน** - กางและพับเก็บใน 1 นาที (ค่าเช่า 450 บาท ต่อ วัน)\n'
          '• **ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว** - น้ำหนักเบาพกพาสะดวก (ค่าเช่า 250 บาท ต่อ วัน)\n\n'
          'คุณลูกค้าสามารถแตะดูรายละเอียดเพิ่มเติมจากการ์ดอุปกรณ์ด้านล่างนี้ได้เลยนะคะ';

      const message = ChatMessage(
        id: 'assistant-filter-unmentioned-card-test',
        role: ChatMessageRole.assistant,
        content: responseContent,
        recommendedItems: [
          RecommendedItem(
            id: 19,
            name: 'เต็นท์ Coleman Instant Cabin 4 คน',
            price: 450,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
            description: 'เต็นท์กันฝน',
          ),
          RecommendedItem(
            id: 20,
            name: 'ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว',
            price: 250,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
            description: 'โต๊ะสนาม',
          ),
          RecommendedItem(
            id: 21,
            name: 'ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED',
            price: 180,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
            description: 'เตาแก๊ส',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Items 1 and 2 were mentioned by AI -> must have cards rendered
      expect(find.text('เต็นท์ Coleman Instant Cabin 4 คน'), findsWidgets);
      expect(
        find.text('ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว'),
        findsWidgets,
      );

      // แสดงรายการที่ผ่านการตรวจ ID แล้ว โดยไม่จับชื่อจากคำตอบ
      expect(
        find.text('ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED'),
        findsWidgets,
      );
      expect(find.text('available'), findsNothing);
      expect(find.text('แคมป์ปิงและกิจกรรมกลางแจ้ง'), findsNothing);
      expect(find.text('ดูรายละเอียด'), findsNothing);
    });

    testWidgets('renders valid Markdown and catalog card names directly', (
      tester,
    ) async {
      const responseContent =
          'ยินดีจัดหาอุปกรณ์แคมป์ปิ้งพร้อมใช้งานให้ค่ะ ขอแนะนำรายการที่มีในระบบนะคะ:\n\n'
          '**เต็นท์ Coleman Instant Cabin 4 คน**\n\n'
          '- **รายละเอียด**: เต็นท์กันฝนและลมแรง กางและพับเก็บเสร็จใน 1 นาที\n'
          '- ราคา: 450 บาทต่อวัน\n\n'
          '**ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว**\n\n'
          '- **รายละเอียด**: โต๊ะพับอลูมิเนียมพร้อมเก้าอี้ 4 ตัว น้ำหนักเบาพกพาสะดวก\n'
          '- ราคา: 250 บาทต่อวัน\n\n'
          'เชิญแตะดูรายละเอียดเพิ่มเติมจากการ์ดอุปกรณ์ด้านล่างนี้ได้เลยนะคะ';

      const message = ChatMessage(
        id: 'assistant-structured-device-format-test',
        role: ChatMessageRole.assistant,
        content: responseContent,
        recommendedItems: [
          RecommendedItem(
            id: 19,
            name: 'เต็นท์ Coleman Instant Cabin 4 คน',
            price: 450,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
            description: 'เต็นท์กันฝน',
          ),
          RecommendedItem(
            id: 20,
            name: 'ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว',
            price: 250,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
            description: 'โต๊ะสนาม',
          ),
          RecommendedItem(
            id: 21,
            name: 'ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED',
            price: 180,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'แคมป์ปิงและกิจกรรมกลางแจ้ง',
            description: 'เตาแก๊ส',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatMessageBubble(message: message, onRentPressed: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cards must render with clean item names (without "ชื่ออุปกรณ์: " on the card)
      expect(find.text('เต็นท์ Coleman Instant Cabin 4 คน'), findsWidgets);
      expect(
        find.text('ชุดโต๊ะพับและเก้าอี้สนาม Naturehike 4 ตัว'),
        findsWidgets,
      );
      expect(
        find.text('ชื่ออุปกรณ์: เต็นท์ Coleman Instant Cabin 4 คน'),
        findsNothing,
      );

      // การ์ดใช้รายการจากผลลัพธ์แบบมีโครงสร้าง
      expect(
        find.text('ชุดเตาแก๊สสนามและหม้อแคมป์ปิ้ง พร้อมตะเกียง LED'),
        findsWidgets,
      );
    });

    testWidgets(
      'renders bold device titles directly without ชื่ออุปกรณ์, formats รายละเอียด/ราคาเช่า bold, and converts units/prices to Thai integer format',
      (tester) async {
        const responseContent =
            'น้องยืมหน่อยขอแนะนำมือถือและอุปกรณ์สื่อสารพร้อมใช้งานในระบบนะคะ:\n\n'
            '**iPhone 15 Pro 128GB**\n'
            '- **รายละเอียด:** สมาร์ตโฟนชิป A17 Pro กล้องระดับโปร 48MP\n'
            '- **ราคาเช่า:** 800 บาท ต่อ วัน\n\n'
            '**Samsung Galaxy S24 Ultra**\n'
            '- **รายละเอียด:** สมาร์ตโฟนแฟลกชิปพร้อมปากกา S-Pen\n'
            '- **ราคาเช่า:** 850 บาท ต่อ วัน\n\n'
            'คุณพี่สามารถแตะดูการ์ดอุปกรณ์ด้านล่างเพื่อทำรายการต่อได้เลยนะคะ';

        const message = ChatMessage(
          id: 'assistant-clean-bold-title-test',
          role: ChatMessageRole.assistant,
          content: responseContent,
          recommendedItems: [
            RecommendedItem(
              id: 10,
              name: 'iPhone 15 Pro 128GB',
              price: 800,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'โทรศัพท์และอุปกรณ์สื่อสาร',
              description: 'สมาร์ตโฟนชิป A17 Pro',
            ),
            RecommendedItem(
              id: 11,
              name: 'Samsung Galaxy S24 Ultra',
              price: 850,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'โทรศัพท์และอุปกรณ์สื่อสาร',
              description: 'สมาร์ตโฟนแฟลกชิป',
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

        // Must NOT find "ชื่ออุปกรณ์" anywhere in the text
        expect(find.textContaining('ชื่ออุปกรณ์'), findsNothing);

        // Bold titles and details are rendered
        expect(find.textContaining('800 บาท ต่อ วัน'), findsWidgets);
        expect(find.textContaining('850 บาท ต่อ วัน'), findsWidgets);
        expect(find.textContaining('daily'), findsNothing);
        expect(find.textContaining('800.0'), findsNothing);
        expect(find.textContaining('850.0'), findsNothing);

        // Recommended cards for both items are rendered
        expect(find.text('iPhone 15 Pro 128GB'), findsWidgets);
        expect(find.text('Samsung Galaxy S24 Ultra'), findsWidgets);
      },
    );

    testWidgets(
      'card visibility follows structured IDs regardless of answer wording',
      (tester) async {
        const negativeText =
            'ขณะนี้ทางยืมหน่อยยังไม่มีบริการให้เช่าเสื้อผ้าหรือสูทสากลสำหรับออกงานค่ะ';
        const message = ChatMessage(
          id: 'negative-test-1',
          role: ChatMessageRole.assistant,
          content: negativeText,
          recommendedItems: [
            RecommendedItem(
              id: 1,
              name: 'Dyson V12 Detect Slim',
              price: 450,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
              description: 'เครื่องดูดฝุ่นไร้สาย',
            ),
            RecommendedItem(
              id: 2,
              name: 'Wanbo T2 Max New',
              price: 350,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
              description: 'โปรเจกเตอร์',
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

        // The negative message is rendered
        expect(
          find.textContaining('ยังไม่มีบริการให้เช่าเสื้อผ้าหรือสูทสากล'),
          findsOneWidget,
        );

        // ไม่เดารายการสินค้าหรือคำปฏิเสธจากข้อความ
        expect(find.byType(RecommendedItemCard), findsNWidgets(2));
        expect(find.text('Dyson V12 Detect Slim'), findsOneWidget);
        expect(find.text('Wanbo T2 Max New'), findsOneWidget);
      },
    );

    testWidgets(
      'renders recommended item cards when AI offers alternative recommendations even if response notes exact item is not available',
      (tester) async {
        const responseText =
            'ขณะนี้ระบบของเรายังไม่มีคอมพิวเตอร์สำหรับเล่นเกมโดยเฉพาะค่ะ แต่เรามีเครื่องเล่นเกมพกพาและคอนโซลที่ตอบโจทย์ความบันเทิงแทนได้นะคะ ขอแนะนำเป็นทางเลือกเสริมดังนี้ค่ะ:\n\n'
            '**PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น**\n'
            '• รายละเอียด: เครื่องเล่นเกม PS5 พร้อมจอย DualSense และเกมยอดนิยม\n'
            '• ราคาเช่า: 700 บาท ต่อ วัน\n\n'
            '**Nintendo Switch OLED พร้อมจอย 4 ตัว**\n'
            '• รายละเอียด: เครื่องเล่นเกมพกพาหน้าจอ OLED 7 นิ้ว พร้อมจอยคอนและเกมปาร์ตี้\n'
            '• ราคาเช่า: 400 บาท ต่อ วัน\n\n'
            'คุณผู้ใช้งานสามารถแตะดูรายละเอียดเพิ่มเติมที่การ์ดด้านล่างนี้ได้เลยนะคะ';

        const message = ChatMessage(
          id: 'alternative-recommendation-test',
          role: ChatMessageRole.assistant,
          content: responseText,
          recommendedItems: [
            RecommendedItem(
              id: 1,
              name: 'PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น',
              price: 700,
              unit: 'วัน',
              imageUrl: '',
              status: 'available',
              category: 'เกมและอุปกรณ์เล่นเกม',
              description: 'เครื่องเกมคอนโซล',
            ),
            RecommendedItem(
              id: 2,
              name: 'Nintendo Switch OLED พร้อมจอย 4 ตัว',
              price: 400,
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

        // Cards must be rendered for both recommended alternative items
        expect(find.byType(RecommendedItemCard), findsNWidgets(2));
        expect(
          find.text('PlayStation 5 พร้อมจอย 2 ตัวและเกม 3 แผ่น'),
          findsWidgets,
        );
        expect(find.text('Nintendo Switch OLED พร้อมจอย 4 ตัว'), findsWidgets);
      },
    );
  });
}
