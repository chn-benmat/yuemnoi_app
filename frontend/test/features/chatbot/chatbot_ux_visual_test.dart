import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/entities/chatbot_failure.dart';
import 'package:frontend/features/chatbot/domain/repositories/chatbot_repository.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_state.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';
import 'package:frontend/features/chatbot/presentation/widgets/ai_summary_bottom_sheet.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chatbot_state_card.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';
import 'package:frontend/features/chatbot/presentation/widgets/interactive_questionnaire_card.dart';

const _questions = [
  ClarificationQuestion(
    id: 'usage',
    title: 'คุณจะใช้กล้องถ่ายอะไรเป็นหลัก?',
    options: [
      'ถ่ายภาพงานอีเวนต์',
      'ถ่ายวิดีโอ',
      'ถ่ายสินค้า',
      'ใช้งานทั่วไป',
      'เรียนถ่ายภาพ',
    ],
  ),
  ClarificationQuestion(
    id: 'budget',
    title: 'งบประมาณต่อวันเท่าไหร่?',
    options: ['ไม่เกิน 500 บาท', '500–1,000 บาท'],
  ),
];
const _understanding = ChatUnderstanding(
  requestScope: 'catalog',
  informationSufficient: true,
  nextAction: 'answer',
  responseFlow: 'standard',
  responseKind: 'recommendation',
);
const _sampleItem = RecommendedItem(
  id: 7,
  name: 'ชุดเลนส์สำหรับถ่ายภาพ',
  price: 350,
  unit: 'วัน',
  imageUrl: 'assets/images/chat_lens_set.png',
  status: 'พร้อมให้เช่า',
  category: 'กล้องและอุปกรณ์',
  description: 'ข้อมูลตัวอย่างสำหรับตรวจหน้าจอ',
);
const _summary = ChatMessage(
  id: 'preview-assistant',
  role: ChatMessageRole.assistant,
  content: 'เปิดรายละเอียดเพื่อดูข้อมูลและเงื่อนไขของแต่ละรายการ',
  userQuery: 'ถ่ายงานในห้อง งบ 500 บาทต่อวัน',
  responseDuration: Duration(seconds: 3),
  activities: ['ค้นหาอุปกรณ์ในระบบ', 'สรุปคำแนะนำ'],
  searchSources: [
    SearchSource(
      title: 'ข้อมูลอุปกรณ์',
      url: 'https://example.com/equipment',
      domain: 'example.com',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Prompt');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Prompt-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<void> screenshot(WidgetTester tester, String name) async {
    const output = String.fromEnvironment('CHATBOT_UX_SCREENSHOT_DIR');
    expect(tester.takeException(), isNull);
    if (output.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('ux-frame')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(output);
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<_PreviewBloc> mount(
    WidgetTester tester,
    ChatbotState state, {
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bloc = _PreviewBloc(state);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('ux-frame'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
          home: BlocProvider<ChatbotBloc>.value(
            value: bloc,
            child: const ChatBotScreen(),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(ChatBotScreen));
      await precacheImage(
        const AssetImage('assets/images/yuemnoi.png'),
        context,
      );
      await precacheImage(
        const AssetImage('assets/images/chat_lens_set.png'),
        context,
      );
    });
    await tester.pump(const Duration(milliseconds: 500));
    return bloc;
  }

  testWidgets('captures eight implemented UI sections', (tester) async {
    await mount(tester, ChatbotState.initial());
    await screenshot(tester, '01-welcome');
    await tester.pumpWidget(const SizedBox());

    final conversation = ChatbotState(
      messages: [
        const ChatMessage(
          role: ChatMessageRole.user,
          content: 'อยากเช่ากล้องถ่ายงานในห้อง งบ 500 บาทต่อวัน',
        ),
        _summary.copyWith(
          content:
              'ลองเริ่มจากกล้องที่ถ่ายในแสงน้อยได้ดี และตรวจสอบเลนส์ที่รวมในชุด',
        ),
      ],
    );
    await mount(tester, conversation);
    await screenshot(tester, '02-conversation');
    await tester.pumpWidget(const SizedBox());

    await mount(
      tester,
      ChatbotState(
        isSending: true,
        messages: const [
          ChatMessage(
            role: ChatMessageRole.user,
            content: 'ช่วยหาอุปกรณ์ถ่ายภาพให้หน่อย',
          ),
          ChatMessage(
            id: 'waiting',
            role: ChatMessageRole.assistant,
            content: '',
            isStreaming: true,
          ),
        ],
        currentStatusMessage: 'กำลังค้นหาอุปกรณ์ในระบบ',
        requestStartTime: DateTime.now(),
      ),
    );
    expect(find.byKey(const Key('chatbot-stop-button')), findsOneWidget);
    await screenshot(tester, '03-generating');
    await tester.pumpWidget(const SizedBox());

    final questioning = ChatbotState(
      messages: [
        const ChatMessage(
          role: ChatMessageRole.user,
          content: 'อยากเช่ากล้องถ่ายงาน',
        ),
        _summary.copyWith(
          content: 'ขอรายละเอียดอีกนิด เพื่อหาตัวเลือกให้เหมาะขึ้น',
          questions: _questions,
        ),
      ],
    );
    await mount(tester, questioning);
    expect(find.byType(InteractiveQuestionnaireCard), findsOneWidget);
    await screenshot(tester, '04-questionnaire');
    await tester.pumpWidget(const SizedBox());

    await mount(
      tester,
      ChatbotState(
        messages: [
          _summary.copyWith(
            content:
                '**ชุดเลนส์สำหรับถ่ายภาพ**\n\n'
                '- **รายละเอียด**: ชุดเลนส์สำหรับงานถ่ายภาพในห้อง\n'
                '- ราคา: 350 บาทต่อวัน',
            recommendedItems: const [_sampleItem],
            understanding: _understanding,
          ),
        ],
      ),
    );
    expect(find.byType(RecommendedItemCard), findsOneWidget);
    expect(find.text('ดูรายละเอียด'), findsNothing);
    await screenshot(tester, '05-recommendations');
    await tester.pumpWidget(const SizedBox());

    await mount(tester, const ChatbotState(messages: [_summary]));
    await tester.tap(find.text('สรุปคำแนะนำ 3 วินาที >'));
    await tester.pumpAndSettle();
    await screenshot(tester, '06-summary');
    expect(find.byType(AISummaryBottomSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await mount(
      tester,
      const ChatbotState(
        messages: [
          ChatMessage(
            role: ChatMessageRole.user,
            content: 'ต้องการเช่ากล้องถ่ายงาน',
          ),
        ],
      ),
    );
    await tester.tap(find.byTooltip('คัดลอกหรือแก้ไขข้อความ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chatbot-edit-message-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chatbot-editing-banner')), findsOneWidget);
    await screenshot(tester, '07-editing');
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('ux-frame'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: Scaffold(
            appBar: AppBar(title: const Text('สถานะและทางไปต่อ')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ChatbotStateCard(
                    title: 'ยังไม่พบอุปกรณ์ที่ตรง',
                    description: 'ลองปรับงบหรือบอกประเภทอุปกรณ์เพิ่มเติม',
                    icon: Icons.search_rounded,
                    actionLabel: 'ปรับคำถาม',
                    onAction: () {},
                  ),
                  const SizedBox(height: 16),
                  ChatbotFailureCard(
                    failure: const ChatbotFailure(
                      messageId: 'network',
                      message: 'ลองอีกครั้งได้ โดยไม่ต้องพิมพ์ใหม่',
                      isRetryable: true,
                    ),
                    onRetry: () {},
                    onRevise: () {},
                  ),
                  const SizedBox(height: 16),
                  ChatbotFailureCard(
                    failure: ChatbotFailure(
                      messageId: 'quota',
                      message: 'ลองใหม่ตามเวลารอที่ได้รับจากบริการ',
                      isRetryable: true,
                      errorCode: 'providers_rate_limited',
                      retryAvailableAt: DateTime.now().add(
                        const Duration(seconds: 60),
                      ),
                    ),
                    onRetry: () {},
                    onRevise: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await screenshot(tester, '08-empty-error-quota');
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [240.0, 320.0, 390.0, 430.0]) {
    testWidgets(
      'chat and composer remain usable width=$width scale=2 keyboard',
      (tester) async {
        await mount(
          tester,
          const ChatbotState(messages: []),
          size: Size(width, 480),
          scale: 2,
          keyboard: 180,
        );
        await screenshot(tester, '09-welcome-$width-large-keyboard');
        await tester.enterText(
          find.byKey(const Key('chatbot-message-field')),
          'ถ่ายงานในห้อง',
        );
        await tester.pump();
        expect(find.byKey(const Key('chatbot-send-button')), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const Key('chatbot-send-button')))
              .shortestSide,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        var scenarioIndex = 0;
        for (final state in [
          ChatbotState(
            messages: [
              _summary.copyWith(
                content: '### อุปกรณ์ที่เหมาะ\n- **กล้อง** สำหรับถ่ายในห้อง',
                recommendedItems: const [_sampleItem],
                understanding: _understanding,
              ),
            ],
          ),
          ChatbotState(messages: [_summary.copyWith(questions: _questions)]),
          const ChatbotState(
            messages: [
              ChatMessage(
                id: 'network',
                role: ChatMessageRole.assistant,
                content: 'เครือข่ายผิดพลาด',
              ),
            ],
            failure: ChatbotFailure(
              messageId: 'network',
              message: 'ลองอีกครั้งได้โดยไม่ต้องพิมพ์ใหม่',
              isRetryable: true,
            ),
          ),
          const ChatbotState(
            isSending: true,
            messages: [
              ChatMessage(
                role: ChatMessageRole.assistant,
                content: '',
                isStreaming: true,
              ),
            ],
          ),
        ]) {
          await mount(
            tester,
            state,
            size: Size(width, 480),
            scale: 2,
            keyboard: 180,
          );
          expect(tester.takeException(), isNull);
          await screenshot(tester, '10-state-$width-${scenarioIndex++}');
          if (state.messages.any((m) => m.questions.isNotEmpty)) {
            for (final key in [
              'chatbot-questionnaire-option-เรียนถ่ายภาพ',
              'chatbot-questionnaire-skip',
              'chatbot-questionnaire-custom-input',
            ]) {
              final target = find.byKey(Key(key));
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              expect(target.hitTestable(), findsOneWidget);
              expect(
                tester.getSize(target).shortestSide,
                greaterThanOrEqualTo(48),
              );
            }
          }
          await tester.pumpWidget(const SizedBox());
        }
        await mount(
          tester,
          const ChatbotState(
            messages: [
              ChatMessage(role: ChatMessageRole.user, content: 'หากล้อง'),
            ],
          ),
          size: Size(width, 480),
          scale: 2,
          keyboard: 180,
        );
        await tester.ensureVisible(find.byTooltip('คัดลอกหรือแก้ไขข้อความ'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('คัดลอกหรือแก้ไขข้อความ'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chatbot-edit-message-action')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('บันทึกแก้ไข'), findsOneWidget);
        expect(find.text('ยกเลิก'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await screenshot(tester, '11-editing-$width-large-keyboard');
        final cancel = find.byKey(const Key('chatbot-cancel-edit-button'));
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        expect(cancel.hitTestable(), findsOneWidget);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chatbot-editing-banner')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'inline questionnaire keeps partial answers after scrolling out of view',
    (tester) async {
      final state = ChatbotState(
        messages: [
          const ChatMessage(
            role: ChatMessageRole.user,
            content: 'อยากเช่ากล้อง',
          ),
          _summary.copyWith(
            content: List.filled(12, 'รายละเอียดประกอบคำถาม').join('\n'),
            questions: _questions,
          ),
        ],
      );
      await mount(tester, state);
      final list = find.byKey(const Key('chatbot-conversation'));
      final option = find.byKey(
        const Key('chatbot-questionnaire-option-ถ่ายภาพงานอีเวนต์'),
      );
      await tester.scrollUntilVisible(
        option,
        250,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pump(const Duration(milliseconds: 250));
      final before = tester.state<InteractiveQuestionnaireCardState>(
        find.byType(InteractiveQuestionnaireCard),
      );
      expect(before.partialAnswers.single.text, 'ถ่ายภาพงานอีเวนต์');
      await tester.drag(list, const Offset(0, 1500));
      await tester.pumpAndSettle();
      final after = tester.state<InteractiveQuestionnaireCardState>(
        find.byType(InteractiveQuestionnaireCard),
      );
      expect(identical(before, after), true);
      expect(after.partialAnswers.single.text, 'ถ่ายภาพงานอีเวนต์');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'final cards do not move a reader away from earlier streamed text',
    (tester) async {
      final streaming = ChatMessage(
        id: 'reading-response',
        role: ChatMessageRole.assistant,
        content: 'รายละเอียดที่กำลังอ่าน\n' * 50,
        isStreaming: true,
      );
      const user = ChatMessage(
        id: 'reading-user',
        role: ChatMessageRole.user,
        content: 'ช่วยเลือกอุปกรณ์ให้หน่อย',
      );
      final bloc = await mount(
        tester,
        ChatbotState(messages: [user, streaming], isSending: true),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('chatbot-conversation')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(500));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 260);
      await tester.pump(const Duration(milliseconds: 200));
      final readingOffset = scrollable.position.pixels;
      bloc.show(
        ChatbotState(
          messages: [
            user,
            streaming.copyWith(
              isStreaming: false,
              recommendedItems: [_sampleItem],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecommendedItemCard), findsOneWidget);
      expect(
        scrollable.position.pixels,
        moreOrLessEquals(readingOffset, epsilon: 1),
      );
      await tester.tap(
        find.byKey(const Key('chatbot-scroll-to-bottom-button')),
      );
      await tester.pumpAndSettle();
      expect(
        scrollable.position.pixels,
        moreOrLessEquals(scrollable.position.maxScrollExtent, epsilon: 1),
      );
    },
  );

  testWidgets(
    'questionnaire, cards and summary support large text without clipping',
    (tester) async {
      tester.view.physicalSize = const Size(240, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final content in [
        InteractiveQuestionnaireCard(
          questions: _questions,
          onCompleted: (_) {},
          onDismiss: () {},
          onCustomInput: () {},
        ),
        RecommendedItemCard(item: _sampleItem, onPressed: () {}),
        AISummaryBottomSheet(message: _summary),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: SingleChildScrollView(child: content)),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}

class _PreviewBloc extends ChatbotBloc {
  _PreviewBloc(ChatbotState state)
    : super(sendMessage: SendChatMessageUseCase(_NoRequests())) {
    emit(state);
  }

  void show(ChatbotState state) => emit(state);
}

class _NoRequests implements ChatbotRepository {
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
