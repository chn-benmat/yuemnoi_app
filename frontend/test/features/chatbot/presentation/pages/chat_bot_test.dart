import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/repositories/chatbot_repository.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_event.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';

class FakeChatbotRepository implements ChatbotRepository {
  int callCount = 0;
  String? latestQuery;
  List<ChatMessage>? latestHistory;

  @override
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async {
    callCount += 1;
    latestQuery = query;
    latestHistory = history;
    return const ChatResponse(
      answer: 'แนะนำ Canon EOS R5 สำหรับงานนี้ค่ะ',
      recommendedItems: [
        RecommendedItem(
          id: 7,
          name: 'Canon EOS R5',
          price: 500,
          unit: 'สัปดาห์',
          imageUrl: '',
          status: 'available',
          category: 'camera',
          description: 'กล้องระดับมืออาชีพ',
        ),
      ],
    );
  }

  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async* {
    callCount += 1;
    latestQuery = query;
    latestHistory = history;
    yield const ChatMetadataEvent(
      mode: 'recommendation',
      recommendedItems: [
        RecommendedItem(
          id: 7,
          name: 'Canon EOS R5',
          price: 500,
          unit: 'สัปดาห์',
          imageUrl: '',
          status: 'available',
          category: 'camera',
          description: 'กล้องระดับมืออาชีพ',
        ),
      ],
    );
    yield const ChatDeltaEvent(text: 'แนะนำ Canon EOS R5 สำหรับงานนี้ค่ะ');
    yield const ChatDoneEvent(
      recommendedItems: [
        RecommendedItem(
          id: 7,
          name: 'Canon EOS R5',
          price: 500,
          unit: 'สัปดาห์',
          imageUrl: '',
          status: 'available',
          category: 'camera',
          description: 'กล้องระดับมืออาชีพ',
        ),
      ],
    );
  }

  @override
  void close() {}
}

class PendingChatbotRepository implements ChatbotRepository {
  final Completer<ChatResponse> response = Completer<ChatResponse>();
  final StreamController<ChatStreamEvent> streamController =
      StreamController<ChatStreamEvent>.broadcast();

  @override
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) {
    return response.future;
  }

  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) {
    return streamController.stream;
  }

  @override
  void close() {
    streamController.close();
  }
}

class SequenceChatbotRepository implements ChatbotRepository {
  int callCount = 0;

  String answerFor(int index) =>
      'คำตอบลำดับ $index สำหรับทดสอบประวัติการสนทนา '
      'ข้อความนี้มีความยาวเพียงพอให้รายการแชทเลื่อนออกจากหน้าจอค่ะ';

  @override
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async {
    callCount += 1;
    return ChatResponse(answer: answerFor(callCount));
  }

  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async* {
    callCount += 1;
    yield ChatDeltaEvent(text: answerFor(callCount));
    yield const ChatDoneEvent();
  }

  @override
  void close() {}
}

void main() {
  testWidgets('reprocesses an edited user message and replaces the AI answer', (
    tester,
  ) async {
    final repository = FakeChatbotRepository();
    final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('chatbot-message-field')),
      'ข้อความเดิม',
    );
    await tester.tap(find.byKey(const Key('chatbot-send-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    await tester.longPress(find.byKey(const ValueKey('chat-user-ข้อความเดิม')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('chatbot-message-action-sheet')),
      findsOneWidget,
    );
    expect(find.text('แก้ไข'), findsOneWidget);
    expect(find.text('คัดลอก'), findsOneWidget);
    expect(
      find.byKey(const Key('chatbot-copy-message-action')),
      findsOneWidget,
    );
    expect(find.text('ตอบกลับ'), findsNothing);
    expect(find.text('ลบ'), findsNothing);

    await tester.tap(find.byKey(const Key('chatbot-edit-message-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chatbot-editing-banner')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chatbot-message-field')))
          .controller!
          .text,
      'ข้อความเดิม',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('chatbot-send-button')))
          .tooltip,
      'บันทึกแก้ไข',
    );

    await tester.enterText(
      find.byKey(const Key('chatbot-message-field')),
      'ข้อความที่แก้แล้ว',
    );
    await tester.tap(find.byKey(const Key('chatbot-send-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('ข้อความเดิม'), findsNothing);
    expect(find.text('ข้อความที่แก้แล้ว'), findsOneWidget);
    expect(find.byKey(const Key('chatbot-editing-banner')), findsNothing);
    expect(repository.callCount, 2);
    expect(repository.latestQuery, 'ข้อความที่แก้แล้ว');
    expect(repository.latestHistory, const []);
    expect(find.text('แนะนำ Canon EOS R5 สำหรับงานนี้ค่ะ'), findsOneWidget);
  });

  testWidgets('shows thinking dots then reveals the AI answer progressively', (
    tester,
  ) async {
    const answer = 'กำลังแสดงคำตอบทีละตัวอักษรค่ะ';
    final repository = PendingChatbotRepository();
    final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final composerRect = tester.getRect(
      find.byKey(const Key('chatbot-composer')),
    );
    expect(composerRect.left, greaterThan(0));
    expect(composerRect.right, lessThan(tester.view.physicalSize.width));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsNothing);
    expect(
      find.byKey(const Key('chatbot-add-rental-item-button')),
      findsNothing,
    );

    final sendButtonContainer = tester.widget<Container>(
      find.byKey(const Key('chatbot-send-gradient')),
    );
    final sendButtonDecoration =
        sendButtonContainer.decoration! as BoxDecoration;
    final sendButtonGradient = sendButtonDecoration.gradient! as LinearGradient;
    expect(sendButtonGradient.begin, Alignment.topLeft);
    expect(sendButtonGradient.end, Alignment.bottomRight);
    expect(sendButtonGradient.colors, const [
      AppColors.gradient1,
      AppColors.gradient2,
    ]);

    await tester.enterText(
      find.byKey(const Key('chatbot-message-field')),
      'โอเค',
    );
    await tester.tap(find.byKey(const Key('chatbot-send-button')));
    await tester.pump();

    final userBubble = find.byKey(const ValueKey('chat-user-โอเค'));
    expect(tester.getSize(userBubble).width, lessThan(120));

    final thinkingDots = find.byKey(const Key('chatbot-thinking-dots'));
    expect(thinkingDots, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.widget<Text>(thinkingDots).data,
      isIn(const ['.', '..', '...']),
    );

    repository.streamController.add(
      const ChatDeltaEvent(text: 'กำลังแสดงคำตอบ'),
    );
    await tester.pump(const Duration(milliseconds: 51));

    // รอแอนิเมชันตัวอักษรหลังการรวมข้อความจากสตรีม
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('กำลังแสดงคำตอบ'), findsOneWidget);
    expect(thinkingDots, findsNothing);

    repository.streamController.add(
      const ChatDeltaEvent(text: 'ทีละตัวอักษรค่ะ'),
    );
    await tester.pump(const Duration(milliseconds: 51));

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(answer), findsOneWidget);

    repository.streamController.add(const ChatDoneEvent());
    await repository.streamController.close();
    await tester.pump();
  });

  testWidgets('shows a jump button and does not replay old AI responses', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final repository = SequenceChatbotRepository();
    final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
      ),
    );

    for (var index = 1; index <= 6; index += 1) {
      bloc.add(ChatbotMessageSubmitted('คำถามลำดับ $index'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
    }

    final firstAnswer = repository.answerFor(1);
    expect(find.text(firstAnswer), findsNothing);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(180);
    await tester.pumpAndSettle();

    expect(find.text(firstAnswer), findsOneWidget);

    final scrollControl = find.byKey(
      const Key('chatbot-scroll-to-bottom-control'),
    );
    expect(tester.widget<AnimatedScale>(scrollControl).scale, 1);

    await tester.tap(find.byKey(const Key('chatbot-scroll-to-bottom-button')));
    await tester.pumpAndSettle();

    expect(
      scrollable.position.pixels,
      moreOrLessEquals(scrollable.position.maxScrollExtent, epsilon: 1),
    );
    expect(tester.widget<AnimatedScale>(scrollControl).scale, 0);
  });

  testWidgets('submits a question and renders the AI product response', (
    tester,
  ) async {
    final repository = FakeChatbotRepository();
    final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Prompt'),
        home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('chatbot-message-field')),
      'ควรเช่ากล้องรุ่นไหนดี',
    );
    await tester.tap(find.byKey(const Key('chatbot-send-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(repository.latestQuery, 'ควรเช่ากล้องรุ่นไหนดี');
    expect(repository.latestHistory, isEmpty);
    expect(find.text('ควรเช่ากล้องรุ่นไหนดี'), findsOneWidget);
    expect(find.text('แนะนำ Canon EOS R5 สำหรับงานนี้ค่ะ'), findsOneWidget);
    expect(find.text('Canon EOS R5'), findsOneWidget);
    expect(find.textContaining('500 ฿'), findsOneWidget);
    expect(find.byType(RecommendedItemCard), findsOneWidget);
    expect(find.text('รายละเอียด'), findsNothing);
    expect(find.text('ปล่อยเช่า'), findsNothing);
  });

  testWidgets('keeps the chat usable on a very narrow phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 480);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final bloc = ChatbotBloc(
      sendMessage: SendChatMessageUseCase(FakeChatbotRepository()),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('chatbot-message-field')),
      'แนะนำกล้องให้หน่อย',
    );
    await tester.tap(find.byKey(const Key('chatbot-send-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    expect(find.text('Canon EOS R5'), findsOneWidget);
    expect(find.byKey(const Key('chatbot-send-button')), findsOneWidget);
  });

  testWidgets(
    'renders Claude-style questionnaire with step badge, collapses into recap card on selection, and receives conditional step 2',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 850);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final repository = FakeDynamicQuestionnaireRepository();
      final sendMessage = SendChatMessageUseCase(repository);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => ChatbotBloc(sendMessage: sendMessage),
            child: const ChatBotScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. User submits open-ended inquiry "เช่าคอม"
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'เช่าคอม',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      // 2. Questionnaire Card appears with Step 1 of 2 badge and options
      expect(
        find.byKey(const Key('chatbot-questionnaire-card')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('chatbot-questionnaire-card')),
          matching: find.text('เช่าคอมไปใช้งานแบบไหน?'),
        ),
        findsOneWidget,
      );
      expect(find.text('ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'), findsWidgets);
      expect(find.text('ตอบเอง'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.byKey(const Key('chatbot-composer')), findsOneWidget);
      expect(find.byKey(const Key('chatbot-message-field')), findsOneWidget);
      expect(repository.callCount, 1);

      // 3. User taps option 1 ("ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)") on Question 1
      final option1 = find.byKey(
        const Key('chatbot-questionnaire-option-ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)'),
      );
      expect(option1, findsOneWidget);
      await tester.tap(option1);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // 4. Step 2 appears locally instantly (0ms latency, callCount is STILL 1!)
      expect(repository.callCount, 1);
      expect(
        find.byKey(const Key('chatbot-questionnaire-card')),
        findsOneWidget,
      );
      expect(find.text('2 of 2'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('chatbot-questionnaire-card')),
          matching: find.text('ระยะเวลาเช่าหรือรูปแบบเครื่องที่ต้องการ?'),
        ),
        findsOneWidget,
      );
      expect(find.text('เน้นพกพา (โน้ตบุ๊ก)'), findsWidgets);

      // 5. User taps option on Question 2 ("เน้นพกพา (โน้ตบุ๊ก)")
      final option2 = find.byKey(
        const Key('chatbot-questionnaire-option-เน้นพกพา (โน้ตบุ๊ก)'),
      );
      expect(option2, findsOneWidget);
      await tester.tap(option2);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // 6. User submits combined answers, triggering immediate recommendation (callCount == 2)
      expect(repository.callCount, 2);
      expect(
        repository.latestQuery,
        'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC), เน้นพกพา (โน้ตบุ๊ก)',
      );
      // รอจนการ์ดปรากฏจริงหลังข้อความและการเลื่อนหน้าจอ
      for (
        var frame = 0;
        frame < 50 &&
            find.byKey(const ValueKey('recommended-item-2')).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('recommended-item-2')), findsOneWidget);
      expect(find.text('Dell Latitude 5420'), findsWidgets);

      // 7. Verify both questions recap cards rendered in chat history
      expect(
        find.byKey(const Key('chatbot-questionnaire-recap-q1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('chatbot-questionnaire-recap-q2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'sends typed text to AI immediately instead of locally advancing the questionnaire',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 850);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final repository = FakeDynamicQuestionnaireRepository();
      final sendMessage = SendChatMessageUseCase(repository);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => ChatbotBloc(sendMessage: sendMessage),
            child: const ChatBotScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Submit "เช่าคอม"
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'เช่าคอม',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('chatbot-questionnaire-card')),
        findsOneWidget,
      );
      expect(find.text('1 of 2'), findsOneWidget);

      // Type custom answer in normal composer
      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'ตัดต่อวิดีโอ 4K',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(repository.callCount, 2);
      expect(repository.latestQuery, 'ตัดต่อวิดีโอ 4K');
      expect(find.text('2 of 2'), findsNothing);
    },
  );

  testWidgets(
    'renders initial quick replies bar on entering chat and submits on tap',
    (tester) async {
      final repository = FakeChatbotRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify quick replies bar is present on entering chat
      expect(
        find.byKey(const Key('chatbot-quick-replies-bar')),
        findsOneWidget,
      );
      expect(find.text('แนะนำอุปกรณ์เช่าหน่อย'), findsOneWidget);
      expect(
        find.text('วิธีการเช่าอุปกรณ์', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text('วิธีปล่อยเช่าอุปกรณ์', skipOffstage: false),
        findsOneWidget,
      );

      // 2. Tap 'แนะนำอุปกรณ์เช่าหน่อย'
      await tester.tap(find.text('แนะนำอุปกรณ์เช่าหน่อย'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(repository.callCount, 1);
      expect(repository.latestQuery, 'แนะนำอุปกรณ์เช่าหน่อย');

      // 3. Verify quick replies bar disappears after message is sent (except on entering chat)
      expect(find.byKey(const Key('chatbot-quick-replies-bar')), findsNothing);
    },
  );

  testWidgets(
    'shows real-time ChatStatusEvent in typing indicator and maintains continuous timer without reset',
    (tester) async {
      final repository = PendingChatbotRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'ค้นหากล้องหน่อย',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pump();

      // Initially shows analyzing intent
      expect(find.textContaining('กำลังวิเคราะห์คำถาม...'), findsOneWidget);

      // Backend sends searching status event
      repository.streamController.add(
        const ChatStatusEvent(
          step: 'searching',
          message: 'กำลังค้นหาอุปกรณ์ในระบบ...',
        ),
      );
      await tester.pump();

      expect(find.textContaining('กำลังค้นหาอุปกรณ์ในระบบ...'), findsOneWidget);

      // Fast-forward 3 seconds by pumping each second interval
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Continuous timer is at least 3 seconds
      expect(find.textContaining('3 วิ'), findsOneWidget);

      // Simulate scroll / rebuild by pumping widget tree
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await tester.pump();

      // Timer must NOT reset to 0; must still be 3 seconds or more
      expect(find.textContaining('0 วิ'), findsNothing);
      expect(find.textContaining('3 วิ'), findsOneWidget);

      // Backend delivers done event
      repository.streamController.add(
        const ChatDeltaEvent(text: 'เจอกล้องแล้วค่ะ'),
      );
      repository.streamController.add(
        const ChatDoneEvent(answer: 'เจอกล้องแล้วค่ะ'),
      );
      await repository.streamController.close();
      await tester.pumpAndSettle();

      // Completed message shows summary status header
      expect(find.textContaining('สรุปคำแนะนำ'), findsOneWidget);
    },
  );

  testWidgets(
    'transforms send button to stop button during streaming and aborts cleanly on tap',
    (tester) async {
      final repository = PendingChatbotRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'ขอคำแนะนำหน่อย',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pump();

      // 1. Send button transforms to Stop button with tooltip and stop icon
      expect(find.byKey(const Key('chatbot-stop-button')), findsOneWidget);
      expect(find.byKey(const Key('chatbot-send-button')), findsNothing);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('chatbot-stop-button')))
            .tooltip,
        'หยุดตอบ',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chatbot-message-field')))
            .enabled,
        isFalse,
      );

      // 2. Stream partial text delta
      repository.streamController.add(
        const ChatDeltaEvent(text: 'นี่คือคำตอบช่วงแรกที่พิมพ์ออกมา'),
      );
      await tester.pump(const Duration(milliseconds: 60));

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('นี่คือคำตอบช่วงแรกที่พิมพ์ออกมา'), findsOneWidget);
      expect(find.byKey(const Key('chatbot-stop-button')), findsOneWidget);

      // 3. User taps Stop button
      await tester.tap(find.byKey(const Key('chatbot-stop-button')));
      await tester.pumpAndSettle();

      // 4. Generation stops, partial text is retained, button returns to Send
      expect(find.text('นี่คือคำตอบช่วงแรกที่พิมพ์ออกมา'), findsOneWidget);
      expect(find.byKey(const Key('chatbot-send-button')), findsOneWidget);
      expect(find.byKey(const Key('chatbot-stop-button')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chatbot-message-field')))
            .enabled,
        isTrue,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'aborts thinking phase cleanly when stop button is tapped before first token',
    (tester) async {
      final repository = PendingChatbotRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'กำลังจะถามคำถาม',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pump();

      // In thinking phase
      expect(find.byKey(const Key('chatbot-stop-button')), findsOneWidget);
      expect(find.textContaining('กำลังวิเคราะห์คำถาม...'), findsOneWidget);

      // User presses Stop before any delta is emitted
      await tester.tap(find.byKey(const Key('chatbot-stop-button')));
      await tester.pumpAndSettle();

      // Friendly stopped message shown, button restored to Send
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('หยุดการตอบกลับแล้ว'), findsOneWidget);
      expect(find.byKey(const Key('chatbot-send-button')), findsOneWidget);
      expect(find.byKey(const Key('chatbot-stop-button')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'stops summary timer immediately when first character is output and keeps it frozen',
    (tester) async {
      final repository = PendingChatbotRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Prompt'),
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'อยากได้กล้องทำงาน',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pump();

      // Thinking phase for 2 seconds
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('2 วิ'), findsOneWidget);

      // First token arrives
      repository.streamController.add(const ChatDeltaEvent(text: 'ส'));
      await tester.pump(const Duration(milliseconds: 60));

      // Header switches to 'สรุปคำแนะนำ' and shows frozen time (at least 2s)
      final summaryHeaderFinder = find.textContaining('สรุปคำแนะนำ');
      expect(summaryHeaderFinder, findsOneWidget);
      final capturedHeader = tester.widget<Text>(summaryHeaderFinder).data!;
      expect(capturedHeader, contains('สรุปคำแนะนำ'));

      // Advance time by 4 more seconds and emit more deltas
      await tester.pump(const Duration(seconds: 2));
      repository.streamController.add(
        const ChatDeltaEvent(text: 'วัสดีครับ มีอุปกรณ์พร้อมให้เช่า'),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 60));

      // Header must maintain the EXACT SAME duration frozen from first token!
      final afterStreamingHeader = tester
          .widget<Text>(summaryHeaderFinder)
          .data!;
      expect(afterStreamingHeader, equals(capturedHeader));

      // Done event arrives
      repository.streamController.add(const ChatDoneEvent());
      await repository.streamController.close();
      await tester.pumpAndSettle();

      // Final state must STILL have the same frozen summary header
      final finalHeader = tester.widget<Text>(summaryHeaderFinder).data!;
      expect(finalHeader, equals(capturedHeader));
    },
  );

  testWidgets(
    'does not render cards when backend delivers empty recommendedItems on done even if metadata had candidate items',
    (tester) async {
      final repository = FakeUnavailableItemRepository();
      final sendMessage = SendChatMessageUseCase(repository);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => ChatbotBloc(sendMessage: sendMessage),
            child: const ChatBotScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chatbot-message-field')),
        'มีเสื้อผ้าหรือสูทสากลให้เช่าไหม',
      );
      await tester.tap(find.byKey(const Key('chatbot-send-button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'ขณะนี้ยังไม่มีอุปกรณ์ประเภทดังกล่าวให้เช่าในระบบค่ะ',
        ),
        findsOneWidget,
      );
      expect(find.text('Dyson V12 Detect Slim'), findsNothing);
    },
  );
}

class FakeDynamicQuestionnaireRepository implements ChatbotRepository {
  int callCount = 0;
  String? latestQuery;

  @override
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async* {
    callCount += 1;
    latestQuery = query;

    if (callCount == 1) {
      yield const ChatMetadataEvent(
        mode: 'questionnaire',
        questions: [
          ClarificationQuestion(
            id: 'q1',
            title: 'เช่าคอมไปใช้งานแบบไหน?',
            options: [
              'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)',
              'จัดอีเวนต์/บูธ (หลายเครื่อง)',
              'เล่นเกม/สเปกแรง',
              'ตัดต่อ/กราฟิก สเปกสูง',
            ],
            step: 1,
            totalSteps: 2,
          ),
          ClarificationQuestion(
            id: 'q2',
            title: 'ระยะเวลาเช่าหรือรูปแบบเครื่องที่ต้องการ?',
            options: [
              'เน้นพกพา (โน้ตบุ๊ก)',
              'ตั้งโต๊ะ (PC สเปกสูง)',
              'เช่าสั้น 1-3 วัน',
              'เช่าระยะยาว (รายเดือน)',
            ],
            step: 2,
            totalSteps: 2,
          ),
        ],
      );
      yield const ChatDeltaEvent(
        text:
            'จะแนะนำอุปกรณ์คอมพิวเตอร์ให้ตรงจุดต้องรู้บริบทก่อน ให้เลือกตอบเร็วๆ ได้เลยนะคะ 😊',
      );
      yield const ChatDoneEvent(
        questions: [
          ClarificationQuestion(
            id: 'q1',
            title: 'เช่าคอมไปใช้งานแบบไหน?',
            options: [
              'ทำงาน/ออฟฟิศ (โน้ตบุ๊ก/PC)',
              'จัดอีเวนต์/บูธ (หลายเครื่อง)',
              'เล่นเกม/สเปกแรง',
              'ตัดต่อ/กราฟิก สเปกสูง',
            ],
            step: 1,
            totalSteps: 2,
          ),
          ClarificationQuestion(
            id: 'q2',
            title: 'ระยะเวลาเช่าหรือรูปแบบเครื่องที่ต้องการ?',
            options: [
              'เน้นพกพา (โน้ตบุ๊ก)',
              'ตั้งโต๊ะ (PC สเปกสูง)',
              'เช่าสั้น 1-3 วัน',
              'เช่าระยะยาว (รายเดือน)',
            ],
            step: 2,
            totalSteps: 2,
          ),
        ],
        suggestedReplies: ['พิมพ์ตอบเอง', 'ข้ามแบบสอบถาม'],
      );
    } else {
      yield const ChatMetadataEvent(
        mode: 'recommendation',
        recommendedItems: [
          RecommendedItem(
            id: 2,
            name: 'Dell Latitude 5420',
            price: 450,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'คอมพิวเตอร์และโน้ตบุ๊ก',
            description: 'โน้ตบุ๊กทำงาน ออฟฟิศ ประมวลผลเร็ว',
          ),
        ],
      );
      yield const ChatDeltaEvent(
        text:
            '### 🎒 อุปกรณ์ที่แนะนำ:\n- **Dell Latitude 5420**: เหมาะสำหรับทำงานทั่วไป พกพาสะดวกค่ะ',
      );
      yield const ChatDoneEvent(
        recommendedItems: [
          RecommendedItem(
            id: 2,
            name: 'Dell Latitude 5420',
            price: 450,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: 'คอมพิวเตอร์และโน้ตบุ๊ก',
            description: 'โน้ตบุ๊กทำงาน ออฟฟิศ ประมวลผลเร็ว',
          ),
        ],
      );
    }
  }

  @override
  void close() {}
}

class FakeUnavailableItemRepository implements ChatbotRepository {
  @override
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async {
    return const ChatResponse(
      answer: 'ขณะนี้ยังไม่มีอุปกรณ์ประเภทดังกล่าวให้เช่าในระบบค่ะ',
      recommendedItems: [],
    );
  }

  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async* {
    yield const ChatMetadataEvent(
      mode: 'recommendation',
      recommendedItems: [
        RecommendedItem(
          id: 99,
          name: 'Dyson V12 Detect Slim',
          price: 450,
          unit: 'วัน',
          imageUrl: '',
          status: 'available',
          category: 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
          description: 'เครื่องดูดฝุ่นไร้สาย',
        ),
      ],
    );
    yield const ChatDeltaEvent(
      text: 'ขณะนี้ยังไม่มีอุปกรณ์ประเภทดังกล่าวให้เช่าในระบบค่ะ',
    );
    yield const ChatDoneEvent(recommendedItems: []);
  }

  @override
  void close() {}
}
