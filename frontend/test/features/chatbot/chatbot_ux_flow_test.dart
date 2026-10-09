import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/repositories/chatbot_repository.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';
import 'package:frontend/features/chatbot/presentation/widgets/interactive_questionnaire_card.dart';

const _questions = [
  ClarificationQuestion(
    id: 'usage',
    title: 'ใช้ถ่ายอะไร?',
    options: ['ภาพนิ่ง', 'วิดีโอ'],
    choices: [
      QuestionChoice(id: 'photo', label: 'ภาพนิ่ง', actionValue: 'photo'),
      QuestionChoice(id: 'video', label: 'วิดีโอ', actionValue: 'video'),
    ],
  ),
  ClarificationQuestion(
    id: 'budget',
    title: 'งบต่อวันเท่าไหร่?',
    options: ['ไม่เกิน 500 บาท'],
    choices: [
      QuestionChoice(id: '500', label: 'ไม่เกิน 500 บาท', actionValue: '500'),
    ],
  ),
];
const _context = ChatSessionContext(
  sessionId: 'flow',
  userGoal: 'หากล้อง',
  questions: _questions,
);
const _understanding = ChatUnderstanding(
  requestScope: 'catalog',
  informationSufficient: true,
  nextAction: 'answer',
  responseFlow: 'standard',
  responseKind: 'recommendation',
);

void main() {
  for (final path in ['complete', 'skip', 'custom', 'custom-first']) {
    testWidgets(
      'welcome → inline questions ($path) → equipment → item detail',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _FlowRepository();
        final bloc = ChatbotBloc(
          sendMessage: SendChatMessageUseCase(repository),
        );
        final router = GoRouter(
          initialLocation: '/chatbot',
          routes: [
            GoRoute(
              path: '/chatbot',
              builder: (_, _) => BlocProvider<ChatbotBloc>.value(
                value: bloc,
                child: const ChatBotScreen(),
              ),
            ),
            // ตรวจว่าปุ่มส่งรหัสจริงให้ route รายละเอียด โดยไม่เรียกบริการจริง
            GoRoute(
              path: '/items/:itemId',
              builder: (_, state) => Scaffold(
                body: Text('รายละเอียด ${state.pathParameters['itemId']}'),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        addTearDown(bloc.close);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        Future<void> tapKey(String key) async {
          final target = find.byKey(Key(key));
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
        }

        await tapKey('chatbot-quick-reply-0');
        expect(repository.requests, isEmpty);
        await tester.enterText(
          find.byKey(const Key('chatbot-message-field')),
          'หากล้องถ่ายงาน',
        );
        await tapKey('chatbot-send-button');
        expect(find.byType(InteractiveQuestionnaireCard), findsOneWidget);
        if (path == 'custom-first') {
          await tapKey('chatbot-questionnaire-custom-input');
          await tester.enterText(
            find.byKey(const Key('chatbot-message-field')),
            'ถ่ายคอนเสิร์ต',
          );
          await tapKey('chatbot-send-button');
          expect(repository.requests, hasLength(1));
        } else {
          await tapKey('chatbot-questionnaire-option-ภาพนิ่ง');
        }
        expect(find.text('ข้อ 2 จาก 2'), findsOneWidget);

        if (path == 'complete') {
          await tapKey('chatbot-questionnaire-prev');
          expect(find.text('ข้อ 1 จาก 2'), findsOneWidget);
          await tapKey('chatbot-questionnaire-option-วิดีโอ');
          await tapKey('chatbot-questionnaire-option-ไม่เกิน 500 บาท');
          expect(repository.requests.last.answers.map((a) => a.optionId), [
            'video',
            '500',
          ]);
        } else if (path == 'custom-first') {
          await tapKey('chatbot-questionnaire-option-ไม่เกิน 500 บาท');
          expect(repository.requests.last.answers.first.text, 'ถ่ายคอนเสิร์ต');
          expect(repository.requests.last.answers.last.optionId, '500');
          expect(find.text('ถ่ายคอนเสิร์ต'), findsOneWidget);
        } else if (path == 'skip') {
          await tapKey('chatbot-questionnaire-skip');
          expect(repository.requests.last.skipped, true);
          expect(repository.requests.last.answers.single.optionId, 'photo');
        } else {
          await tapKey('chatbot-questionnaire-custom-input');
          await tester.enterText(
            find.byKey(const Key('chatbot-message-field')),
            'ขอชุดเบา งบ 500',
          );
          await tapKey('chatbot-send-button');
          expect(repository.requests.last.query, 'ภาพนิ่ง, ขอชุดเบา งบ 500');
          expect(repository.requests.last.activeQuestionId, isNull);
          expect(repository.requests.last.answers.first.optionId, 'photo');
          expect(repository.requests.last.answers.last.questionId, 'budget');
          expect(repository.requests.last.answers.last.text, 'ขอชุดเบา งบ 500');
          expect(find.text('ขอชุดเบา งบ 500'), findsOneWidget);
        }
        expect(repository.requests, hasLength(2));
        expect(repository.requests.last.context, _context);
        expect(bloc.state.messages.last.recommendedItems.single.id, 7);
        final details = find.byKey(const ValueKey('recommended-item-7'));
        await tester.ensureVisible(details);
        await tester.pumpAndSettle();
        await tester.tap(details);
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียด 7'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _FlowRepository implements ChatbotRepository {
  final requests =
      <
        ({
          String query,
          ChatSessionContext? context,
          List<QuestionnaireAnswer> answers,
          bool skipped,
          String? activeQuestionId,
        })
      >[];
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
    requests.add((
      query: query,
      context: context,
      answers: questionnaireAnswers,
      skipped: questionnaireSkipped,
      activeQuestionId: activeQuestionId,
    ));
    if (requests.length == 1) {
      yield const ChatDoneEvent(
        answer: 'ขอข้อมูลอีกนิด',
        questions: _questions,
        context: _context,
        understanding: _understanding,
      );
    } else {
      yield const ChatDoneEvent(
        answer: 'เปิดรายละเอียดเพื่อตรวจเงื่อนไข',
        understanding: _understanding,
        recommendedItems: [
          RecommendedItem(
            id: 7,
            name: 'ชุดกล้อง',
            price: 350,
            unit: 'วัน',
            imageUrl: '',
            status: 'available',
            category: null,
            description: null,
          ),
        ],
      );
    }
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
