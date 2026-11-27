import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chatbot_composer.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chatbot_welcome.dart';

RecommendedItem _item({int? id = 7, String imageUrl = ''}) => RecommendedItem(
  id: id,
  name: 'อุปกรณ์สำหรับทำโปรเจกต์และถ่ายคอนเทนต์ที่มีชื่อยาว',
  price: null,
  unit: '',
  imageUrl: imageUrl,
  status: null,
  category: null,
  description: null,
);

Widget _frame(Widget child, {double scale = 1, bool reduceMotion = false}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets(
    'blank drafts cannot send and long drafts are counted without truncation',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var sends = 0;
      await tester.pumpWidget(
        _frame(
          ChatbotComposer(
            controller: controller,
            focusNode: focus,
            isSending: false,
            onSend: () => sends++,
          ),
        ),
      );
      final send = find.byKey(const Key('chatbot-send-button'));
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      expect(find.byKey(const Key('chatbot-character-counter')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        '   ',
      );
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'หาอุปกรณ์เล่นเกม',
      );
      await tester.pump();
      await tester.tap(send);
      expect(sends, 1);
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'a' * 159,
      );
      await tester.pump();
      expect(find.byKey(const Key('chatbot-character-counter')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'a' * 160,
      );
      await tester.pump();
      expect(find.text('160'), findsOneWidget);
      final longDraft = 'a' * 201;
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        longDraft,
      );
      await tester.pump();
      expect(controller.text, longDraft);
      expect(find.text('201'), findsOneWidget);
      await tester.tap(send);
      expect(sends, 2);
    },
  );

  testWidgets('all five starters fill an editable topic request', (
    tester,
  ) async {
    String? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatbotWelcome(onSelect: (value) => draft = value),
        ),
      ),
    );
    const topics = [
      'ถ่ายคอนเทนต์',
      'ทำโปรเจกต์',
      'ไปทริป',
      'เล่นเกม',
      'เล่นดนตรี',
    ];
    for (final topic in topics) {
      await tester.ensureVisible(find.text(topic));
      await tester.tap(find.text(topic));
      expect(draft, 'ช่วยหาอุปกรณ์สำหรับ$topicให้หน่อย');
    }
  });

  for (final settings in [
    (390.0, 1.0),
    (319.0, 1.0),
    (390.0, 1.5),
    (240.0, 2.0),
  ]) {
    testWidgets(
      'long catalog names and missing fields remain usable at $settings',
      (tester) async {
        tester.view.physicalSize = Size(settings.$1, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final item = _item();
        var opens = 0;
        await tester.pumpWidget(
          _frame(
            RecommendedItemCard(item: item, onPressed: () => opens++),
            scale: settings.$2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('ไม่ระบุราคา'), findsOneWidget);
        expect(find.text('พร้อมให้เช่า'), findsNothing);
        final image = tester.getRect(find.byType(ClipRRect));
        final title = tester.getRect(find.text(item.name));
        if (settings.$1 < 320 || settings.$2 >= 1.5) {
          expect(title.top, greaterThan(image.bottom));
        } else {
          expect(title.left, greaterThan(image.right));
        }
        await tester.tap(find.byKey(const ValueKey('recommended-item-7')));
        expect(opens, 1);
      },
    );
  }

  testWidgets(
    'invalid catalog IDs stay disabled and broken images have a fallback',
    (tester) async {
      var opens = 0;
      for (final id in [null, 0, -1]) {
        await tester.pumpWidget(
          _frame(
            RecommendedItemCard(
              item: _item(
                id: id,
                imageUrl: 'assets/images/missing-equipment.png',
              ),
              onPressed: () => opens++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
        expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
      }
      expect(opens, 0);
    },
  );

  testWidgets(
    'stream text paints immediately and reduced motion reveals final cards directly',
    (tester) async {
      final answer = 'คำตอบที่ได้รับจากสตรีม ' * 80;
      var renders = 0;
      final streaming = ChatMessage(
        id: 'instant',
        role: ChatMessageRole.assistant,
        content: answer,
        isStreaming: true,
      );
      Widget bubble(ChatMessage message) => _frame(
        ChatMessageBubble(
          message: message,
          animateAssistantResponse: true,
          onRentPressed: (_) {},
          onContentRendered: () => renders++,
        ),
        reduceMotion: true,
      );
      await tester.pumpWidget(bubble(streaming));
      expect(find.text(answer), findsOneWidget);
      expect(renders, 0);
      await tester.pumpWidget(
        bubble(
          streaming.copyWith(isStreaming: false, recommendedItems: [_item()]),
        ),
      );
      expect(find.byType(RecommendedItemCard), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(renders, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(renders, 1);
    },
  );
}
