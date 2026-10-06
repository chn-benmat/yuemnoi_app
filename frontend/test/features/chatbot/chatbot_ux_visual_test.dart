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
  });

  Future<void> screenshot(WidgetTester tester, String name) async {
    const output = String.fromEnvironment('CHATBOT_UX_SCREENSHOT_DIR');
    expect(tester.takeException(), isNull);
    if (output.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('ux-frame')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await tester.runAsync(() async {
      final directory = Directory(output);
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
    image.dispose();
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
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
          home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
        ),
      ),
    );
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
            recommendedItems: const [_sampleItem],
            understanding: _understanding,
          ),
        ],
      ),
    );
    expect(find.text('ดูรายละเอียด'), findsOneWidget);
    await screenshot(tester, '05-recommendations');
    await tester.pumpWidget(const SizedBox());

    await mount(tester, const ChatbotState(messages: [_summary]));
    await tester.tap(find.text('ข้อมูลประกอบคำแนะนำ'));
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
}

class _NoRequests implements ChatbotRepository {
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
