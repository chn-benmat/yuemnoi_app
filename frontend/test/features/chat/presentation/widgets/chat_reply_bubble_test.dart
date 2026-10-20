import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_message_composer.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_message_bubble.dart';

ChatMessage reply(String text, {bool isMine = true}) => ChatMessage(
  id: 'reply',
  conversationId: 'conversation',
  senderId: isMine ? 'me' : 'other',
  message: text,
  createdAt: DateTime(2026, 10, 20),
  isMine: isMine,
);

Future<void> pumpBubble(
  WidgetTester tester,
  ChatMessage message, {
  ValueChanged<String>? onQuotedTap,
  ChatMessage? quotedMessage,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: ChatMessageBubble(
            message: message,
            quotedMessage: quotedMessage,
            otherUserName: 'สมชาย',
            onQuotedTap: onQuotedTap,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('legacy multiline booking quote never leaks metadata into reply', (
    tester,
  ) async {
    String? quotedId;
    await pumpBubble(
      tester,
      reply(
        '↩ ตอบกลับ:ตัวเอง|📋 คำขอเช่าอุปกรณ์\n'
        'อุปกรณ์: iPhone 18 Pro Max 256G...|420|https://example.com/item.jpg\n'
        'ยืนยันให้แล้ว',
      ),
      onQuotedTap: (id) => quotedId = id,
    );

    expect(find.text('ยืนยันให้แล้ว'), findsOneWidget);
    expect(find.textContaining('|420|'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    await tester.tap(find.textContaining('คำขอเช่าอุปกรณ์').first);
    expect(quotedId, '420');
    expect(tester.takeException(), isNull);
  });

  testWidgets('text quote appears above a separate answer bubble', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      reply('↩ ตอบกลับ:สมชาย|พร้อมให้เช่าครับ|origin|\nรับทราบครับ'),
    );

    final bubble = find.ancestor(
      of: find.text('รับทราบครับ'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                AppColors.primaryColor,
      ),
    );
    expect(bubble, findsOneWidget);
    expect(
      find.descendant(of: bubble, matching: find.text('พร้อมให้เช่าครับ')),
      findsNothing,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('chat-reply-text-quote')))
          .bottom,
      lessThanOrEqualTo(tester.getRect(bubble).top),
    );
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['normal', 'reply', 'edit']) {
    testWidgets(
      '$mode composer keeps newlines and sends only from its button',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final submitted = <String>[];
        final original = reply('ข้อความเดิม');
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatMessageComposer(
                  controller: controller,
                  onSend: () => submitted.add(controller.text),
                  onCamera: () {},
                  onGallery: () {},
                  replyingMessage: mode == 'reply' ? original : null,
                  editingMessage: mode == 'edit' ? original : null,
                ),
              ),
            ),
          ),
        );
        final field = find.byKey(const ValueKey('chat-message-field'));
        await tester.enterText(field, 'บรรทัดแรก');
        await tester.pump();
        final initialHeight = tester.getSize(field).height;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        expect(submitted, isEmpty);
        const text = 'บรรทัดแรก\nบรรทัดที่สอง\nบรรทัดที่สาม';
        await tester.enterText(field, text);
        await tester.pump();
        expect(tester.getSize(field).height, greaterThan(initialHeight));
        expect(controller.text, text);
        await tester.tap(find.byKey(const ValueKey('send-message-button')));
        expect(submitted, [text]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('attachment toggle preserves the multiline draft and cursor', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var cameraTaps = 0;
    var galleryTaps = 0;
    final submitted = <String>[];
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatMessageComposer(
            controller: controller,
            onSend: () {
              submitted.add(controller.text);
              controller.clear();
            },
            onCamera: () => cameraTaps++,
            onGallery: () => galleryTaps++,
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('chat-message-field'));
    final camera = find.byKey(const ValueKey('camera-button'));
    final gallery = find.byKey(const ValueKey('gallery-button'));
    final toggle = find.byKey(const ValueKey('chat-attachments-toggle'));
    expect(camera, findsOneWidget);
    expect(gallery, findsOneWidget);
    expect(toggle, findsNothing);
    const draft = 'บรรทัดแรก\nบรรทัดที่สอง\nบรรทัดที่สาม';
    await tester.enterText(field, draft);
    await tester.pumpAndSettle();
    final expandedWidth = tester.getSize(field).width;
    final expandedHeight = tester.getSize(field).height;
    final selection = controller.selection;
    expect(camera, findsNothing);
    expect(gallery, findsNothing);
    expect(find.byTooltip('แสดงกล้องและแกลเลอรี'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(camera, findsOneWidget);
    expect(gallery, findsOneWidget);
    expect(toggle, findsNothing);
    expect(tester.getSize(field).width, lessThan(expandedWidth));
    expect(tester.getSize(field).height, lessThan(expandedHeight));
    expect(controller.text, draft);
    expect(controller.selection, selection);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.tap(camera);
    await tester.tap(gallery);
    expect(cameraTaps, 1);
    expect(galleryTaps, 1);
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(camera, findsOneWidget);

    expect(controller.text, draft);
    expect(controller.selection.baseOffset, 3);
    await tester.enterText(field, '$draft!');
    await tester.pumpAndSettle();
    expect(camera, findsNothing);
    await tester.tap(find.byKey(const ValueKey('send-message-button')));
    await tester.pumpAndSettle();
    expect(submitted, ['$draft!']);
    expect(controller.text, isEmpty);
    expect(camera, findsOneWidget);
    expect(gallery, findsOneWidget);
    expect(toggle, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final draft in [
    '\nข้อความล่าสุด',
    List.generate(12, (index) => 'ข้อความบรรทัดที่ ${index + 1}').join('\n'),
  ]) {
    testWidgets(
      'expanding attachments keeps the latest caret visible ${draft.length}',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: ChatMessageComposer(
                controller: controller,
                onSend: () {},
                onCamera: () {},
                onGallery: () {},
              ),
            ),
          ),
        );
        final field = find.byKey(const ValueKey('chat-message-field'));
        await tester.enterText(field, draft);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-attachments-toggle')));
        await tester.pumpAndSettle();
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final caret = editable.renderEditable
            .getLocalRectForCaret(controller.selection.extent)
            .shift(editable.renderEditable.localToGlobal(Offset.zero));
        expect(
          tester.getRect(field).contains(caret.center),
          isTrue,
          reason: 'The latest typed line must stay inside the compact input.',
        );
        expect(controller.text, draft);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a prefilled draft starts with the attachments collapsed', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'ข้อความที่กำลังแก้ไข');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatMessageComposer(
            controller: controller,
            editingMessage: reply('ข้อความเดิม'),
            onSend: () {},
            onCamera: () {},
            onGallery: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('camera-button')), findsNothing);
    expect(find.byKey(const ValueKey('gallery-button')), findsNothing);
    expect(find.byTooltip('แสดงกล้องและแกลเลอรี'), findsOneWidget);
    expect(find.byTooltip('บันทึกแก้ไข'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy item quote hides an embedded message ID and storage URL', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      reply(
        '↩ ตอบกลับ:ตัวเอง|อุปกรณ์: iPhone 18 Pro Max 256G... 420 https://example.com/item.jpg|430|\nรับทราบครับ',
      ),
    );

    expect(find.text('iPhone 18 Pro Max 256G...'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('420'), findsNothing);
    expect(find.text('รับทราบครับ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image quote shows the smaller original above a separate answer', (
    tester,
  ) async {
    final answer = List.filled(8, 'รายละเอียดคำตอบหลายบรรทัด').join('\n');
    await pumpBubble(
      tester,
      reply(
        '↩ ตอบกลับ:ตัวเอง|📷 รูปภาพ|photo|https://example.com/photo.jpg\n$answer',
      ),
    );

    final image = find.byType(CachedNetworkImage);
    expect(image, findsOneWidget);
    expect(tester.getSize(image).height, 136);
    expect(tester.getSize(image).width, lessThanOrEqualTo(176));
    expect(
      tester.getRect(image).bottom,
      lessThanOrEqualTo(tester.getRect(find.text(answer)).top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('product reply restores the original product and rental price', (
    tester,
  ) async {
    const inquiry = ItemInquiryData(
      itemId: 42,
      itemName: 'Canon EOS R50',
      imageUrl: 'https://example.com/camera.jpg',
      price: 5799,
      unitLabel: 'วัน',
    );
    final original = ChatMessage(
      id: 'origin',
      conversationId: 'conversation',
      senderId: 'other',
      message: inquiry.toChatMessagePayload(),
      createdAt: DateTime(2026, 10, 20),
      isMine: false,
    );
    String? quotedId;
    await pumpBubble(
      tester,
      reply('↩ ตอบกลับ:สมชาย|อุปกรณ์: Canon EOS R50|origin|\nยังว่างไหมครับ'),
      quotedMessage: original,
      onQuotedTap: (id) => quotedId = id,
    );

    expect(find.text('Canon EOS R50'), findsOneWidget);
    expect(find.text('5,799 บาท / วัน'), findsOneWidget);
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, inquiry.imageUrl);
    expect(image.fit, BoxFit.contain);
    final card = find.byKey(const ValueKey('chat-reply-media-card'));
    expect(tester.getSize(card).width, 188);
    final answer = find.text('ยังว่างไหมครับ');
    expect(tester.getRect(card).bottom, lessThan(tester.getRect(answer).top));
    final answerBubble = find.ancestor(
      of: answer,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                AppColors.primaryColor,
      ),
    );
    expect(find.descendant(of: answerBubble, matching: card), findsNothing);
    await tester.tap(find.text('Canon EOS R50'));
    expect(quotedId, 'origin');
    expect(tester.takeException(), isNull);
  });

  testWidgets('received media reply fits a narrow screen with larger text', (
    tester,
  ) async {
    String? quotedId;
    await pumpBubble(
      tester,
      reply(
        '↩ ตอบกลับ:ตัวเอง|อุปกรณ์: กล้องพร้อมเลนส์และอุปกรณ์เสริมสำหรับถ่ายวิดีโอ|origin|https://example.com/camera.jpg\nพร้อมให้เช่าครับ',
        isMine: false,
      ),
      textScale: 1.5,
      onQuotedTap: (id) => quotedId = id,
    );
    expect(find.text('สมชายตอบกลับตัวเอง'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-reply-media-card')));
    expect(quotedId, 'origin');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a photo answer keeps its own image separate from the quote', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'reply',
      conversationId: 'conversation',
      senderId: 'me',
      message:
          '↩ ตอบกลับ:สมชาย|📷 รูปภาพ|origin|https://example.com/original.jpg\nภาพเพิ่มเติมครับ',
      imageUrl: 'https://example.com/answer.jpg',
      createdAt: DateTime(2026, 10, 20),
      isMine: true,
    );
    await pumpBubble(tester, message);
    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(images.map((image) => image.imageUrl), [
      'https://example.com/original.jpg',
      'https://example.com/answer.jpg',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer previews the selected photo and can cancel reply', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatMessageComposer(
            controller: controller,
            onSend: () {},
            onCamera: () {},
            onGallery: () {},
            replyingMessage: ChatMessage(
              id: 'photo',
              conversationId: 'conversation',
              senderId: 'other',
              message: '',
              imageUrl: 'https://example.com/photo.jpg',
              createdAt: DateTime(2026, 10, 20),
              isMine: false,
            ),
            onCancelReplyOrEdit: () => cancelled = true,
          ),
        ),
      ),
    );
    expect(find.text('📷 รูปภาพ'), findsOneWidget);
    expect(tester.getSize(find.byType(CachedNetworkImage)), const Size(48, 48));
    await tester.tap(find.byTooltip('ยกเลิกตอบกลับ'));
    expect(cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'received reply identifies its sender and opens the quoted message',
    (tester) async {
      String? quotedId;
      await pumpBubble(
        tester,
        reply(
          '↩ ตอบกลับ:ตัวเอง|พร้อมให้เช่าครับ|origin|\nรับทราบครับ',
          isMine: false,
        ),
        onQuotedTap: (id) => quotedId = id,
      );
      expect(find.text('สมชายตอบกลับตัวเอง'), findsOneWidget);
      await tester.tap(find.text('พร้อมให้เช่าครับ'));
      expect(quotedId, 'origin');
      expect(tester.takeException(), isNull);
    },
  );
}
