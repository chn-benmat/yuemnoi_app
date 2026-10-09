import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/data/models/chat_context_model.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/repositories/chatbot_repository.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_event.dart';
import 'package:frontend/features/chatbot/presentation/widgets/interactive_questionnaire_card.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';

class ContractApiClient extends Mock implements ApiClient {}

const question = ClarificationQuestion(
  id: 'batch:usage',
  title: 'ใช้ที่ไหน',
  dimension: 'location',
  options: ['ช้อยชื่อเดียวกัน', 'ช้อยชื่อเดียวกัน'],
  choices: [
    QuestionChoice(
      id: 'indoor',
      label: 'ช้อยชื่อเดียวกัน',
      actionValue: 'indoor',
    ),
    QuestionChoice(
      id: 'outdoor',
      label: 'ช้อยชื่อเดียวกัน',
      actionValue: 'outdoor',
    ),
  ],
);
const chatContext = ChatSessionContext(
  sessionId: 'current-chat',
  userGoal: 'เลือกอุปกรณ์',
  questions: [question],
  knownFacts: [
    ConversationFact(
      dimension: 'weight',
      value: 'ต้องเบา',
      sourceMessageIds: ['current'],
    ),
  ],
);

class RecordingRepository implements ChatbotRepository {
  final requests =
      <
        ({
          String? sessionId,
          String query,
          String? activeQuestionId,
          ChatSessionContext? context,
          List<QuestionnaireAnswer> answers,
          bool skipped,
          List<ChatMessage> history,
        })
      >[];
  final replies = <ChatDoneEvent>[];
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
      sessionId: sessionId,
      query: query,
      activeQuestionId: activeQuestionId,
      context: context,
      answers: questionnaireAnswers,
      skipped: questionnaireSkipped,
      history: history,
    ));
    yield replies.removeAt(0);
  }

  @override
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) => throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  for (final partial in [false, true]) {
    testWidgets(
      'typed topic switch reaches AI before questionnaire completion: partial=$partial',
      (tester) async {
        const first = ClarificationQuestion(
          id: 'batch:purpose',
          dimension: 'intended_use',
          title: 'นำไปใช้งานอะไร',
          options: ['งานเอกสาร', 'งานภาพ'],
          choices: [
            QuestionChoice(
              id: 'office',
              label: 'งานเอกสาร',
              actionValue: 'office',
            ),
            QuestionChoice(id: 'image', label: 'งานภาพ', actionValue: 'image'),
          ],
          step: 1,
          totalSteps: 2,
        );
        const second = ClarificationQuestion(
          id: 'batch:duration',
          dimension: 'rental_duration',
          title: 'ระยะเวลาเช่า',
          options: ['1 วัน', '1 สัปดาห์'],
          choices: [
            QuestionChoice(id: 'day', label: '1 วัน', actionValue: '1 day'),
            QuestionChoice(
              id: 'week',
              label: '1 สัปดาห์',
              actionValue: '1 week',
            ),
          ],
          step: 2,
          totalSteps: 2,
        );
        const context = ChatSessionContext(
          sessionId: 'interruption',
          userGoal: 'หาอุปกรณ์',
          questions: [first, second],
        );
        final repository = RecordingRepository();
        repository.replies.addAll([
          const ChatDoneEvent(
            answer: 'ขอข้อมูลเพิ่มเติม',
            questions: [first, second],
            context: context,
          ),
          const ChatDoneEvent(
            answer: 'ข้อมูลสินค้าตัวใหม่',
            context: ChatSessionContext(
              sessionId: 'interruption',
              userGoal: 'สินค้าตัวใหม่',
            ),
          ),
        ]);
        final bloc = ChatbotBloc(
          sendMessage: SendChatMessageUseCase(repository),
        );
        addTearDown(bloc.close);
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('chatbot-message-field')),
          'หาอุปกรณ์',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chatbot-send-button')));
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (partial) {
          await tester.tap(
            find.byKey(const Key('chatbot-questionnaire-option-งานเอกสาร')),
          );
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(repository.requests.length, 1);
        await tester.enterText(
          find.byKey(const Key('chatbot-message-field')),
          'เปลี่ยนไปถามสินค้าตัวใหม่',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chatbot-send-button')));
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(repository.requests.length, 2);
        final sent = repository.requests.last;
        expect(sent.query, 'เปลี่ยนไปถามสินค้าตัวใหม่');
        expect(sent.activeQuestionId, partial ? second.id : first.id);
        expect(sent.answers.length, partial ? 1 : 0);
        if (partial) {
          expect(sent.answers.single.questionId, first.id);
          expect(sent.answers.single.optionId, 'office');
        }
        expect(
          sent.answers.any((a) => a.questionId == sent.activeQuestionId),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  late Map<String, dynamic> fixture;
  setUpAll(() {
    fixture =
        jsonDecode(
              File(
                '../ai_service/tests/fixtures/chat_contract.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });

  for (final stream in [false, true]) {
    test(
      'shared Python and Go contract preserves context, IDs, sources: stream=$stream',
      () async {
        final client = ContractApiClient();
        when(() => client.close()).thenReturn(null);
        final response = Map<String, dynamic>.from(fixture['response'] as Map);
        final request = Map<String, dynamic>.from(fixture['request'] as Map);
        when(
          () => client.post(
            any(),
            data: any(named: 'data'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => ApiResponse(
            statusCode: 200,
            data: {
              ...response,
              'answer': response['response'],
              'recommended_items': response['items'],
            },
          ),
        );
        when(
          () => client.postStream(
            any(),
            data: any(named: 'data'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async =>
              Stream.fromIterable((fixture['sse'] as String).split('\n')),
        );
        final source = ChatbotRemoteDataSource(client: client);
        addTearDown(source.close);
        final context = ChatContextModel.fromJson(request['context'])!;
        final answer = QuestionnaireAnswer(
          questionId: context.questions.single.id,
          optionId: 'outdoor',
        );
        final replies = stream
            ? await source
                  .sendMessageStream(
                    query: request['message'] as String,
                    history: [],
                    sessionId: context.sessionId,
                    context: context,
                    questionnaireAnswers: [answer],
                    activeQuestionId: context.questions.single.id,
                  )
                  .toList()
            : <ChatStreamEvent>[];
        final result = stream
            ? replies.whereType<ChatDoneEvent>().single
            : await source.sendMessage(
                query: request['message'] as String,
                history: [],
                sessionId: context.sessionId,
                context: context,
                questionnaireAnswers: [answer],
                activeQuestionId: context.questions.single.id,
              );
        final mappedContext = result is ChatDoneEvent
            ? result.context
            : (result as ChatResponse).context;
        final references = result is ChatDoneEvent
            ? result.references
            : (result as ChatResponse).references;
        expect(mappedContext, context);
        expect(references.first.id, 'rental.request_in_chat');
        final understanding = result is ChatDoneEvent
            ? result.understanding
            : (result as ChatResponse).understanding;
        expect(understanding!.requestScope, 'broad');
        expect(understanding.informationSufficient, isFalse);
        expect(understanding.nextAction, 'clarify');
        expect(understanding.responseFlow, 'general');
        final calls = stream
            ? verify(
                () => client.postStream(
                  any(),
                  data: captureAny(named: 'data'),
                  headers: any(named: 'headers'),
                ),
              )
            : verify(
                () => client.post(
                  any(),
                  data: captureAny(named: 'data'),
                  headers: any(named: 'headers'),
                ),
              );
        final data = calls.captured.single as Map;
        expect(data['context'], ChatContextModel.toJson(context));
        expect(data['active_question_id'], context.questions.single.id);
        expect(data['questionnaire_answers'], [
          {'question_id': context.questions.single.id, 'option_id': 'outdoor'},
        ]);
      },
    );
  }

  test(
    'bounded history keeps complete questions, IDs and long content',
    () async {
      final client = ContractApiClient();
      when(() => client.close()).thenReturn(null);
      when(
        () => client.post(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async =>
            const ApiResponse(statusCode: 200, data: {'answer': 'สำเร็จ'}),
      );
      final source = ChatbotRemoteDataSource(
        client: client,
        historyMaxMessages: 2,
        historyMaxCharacters: 5000,
      );
      addTearDown(source.close);
      final text = List.filled(1601, 'ก').join();
      await source.sendMessage(
        query: 'ต่อ',
        history: [
          const ChatMessage(role: ChatMessageRole.user, content: 'เก่า'),
          ChatMessage(
            role: ChatMessageRole.assistant,
            content: text,
            questions: [
              question.copyWith(
                selectedOption: 'ช้อยชื่อเดียวกัน',
                selectedOptionId: 'outdoor',
              ),
            ],
          ),
          const ChatMessage(role: ChatMessageRole.user, content: 'ล่าสุด'),
        ],
        context: chatContext,
      );
      final data =
          verify(
                () => client.post(
                  any(),
                  data: captureAny(named: 'data'),
                  headers: any(named: 'headers'),
                ),
              ).captured.single
              as Map;
      final history = data['history'] as List;
      expect(history.length, 2);
      final structured =
          jsonDecode((history.first as Map)['content'] as String) as Map;
      expect(structured['answer'], text);
      expect(structured['questions'][0]['id'], question.id);
      expect(structured['questions'][0]['selected_option_id'], 'outdoor');
      expect(structured['questions'][0]['choices'][1]['id'], 'outdoor');
      expect((data['context'] as Map)['known_facts'], isNotEmpty);
    },
  );

  for (final invalid in [
    'data: {"answer":"x","context":{"session_id":false}}',
    'data: {"answer":"x","references":"invalid"}',
    'data: {"answer":"x","request_scope":"broad","information_sufficient":"false","next_action":"clarify","response_flow":"general"}',
    'data: {"answer":17}',
  ]) {
    test('malformed done is an error, not completion: $invalid', () async {
      final client = ContractApiClient();
      when(() => client.close()).thenReturn(null);
      when(
        () => client.postStream(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async =>
            Stream.fromIterable(['event: done', invalid, '', 'data: [DONE]']),
      );
      final source = ChatbotRemoteDataSource(client: client);
      addTearDown(source.close);
      await expectLater(
        source.sendMessageStream(query: 'คำถาม', history: []).toList(),
        throwsA(isA<ChatbotRemoteException>()),
      );
    });
  }

  test('DONE marker alone cannot publish successful completion', () async {
    final client = ContractApiClient();
    when(() => client.close()).thenReturn(null);
    when(
      () => client.postStream(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async => Stream.fromIterable(['data: [DONE]']));
    final source = ChatbotRemoteDataSource(client: client);
    addTearDown(source.close);
    await expectLater(
      source.sendMessageStream(query: 'คำถาม', history: []).toList(),
      throwsA(isA<ChatbotRemoteException>()),
    );
  });

  Future<void> submit(ChatbotBloc bloc, ChatbotEvent event) async {
    final completed = bloc.stream.firstWhere((s) => !s.isSending);
    bloc.add(event);
    await completed.timeout(const Duration(seconds: 2));
  }

  test(
    'choice, free text, skip, edit and topic change use only the remaining chat context',
    () async {
      final repository = RecordingRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(bloc.close);
      const corrected = ChatSessionContext(
        sessionId: 'current-chat',
        userGoal: 'เลือกอุปกรณ์',
        knownFacts: [
          ConversationFact(
            dimension: 'budget',
            value: '900 ต่อวัน',
            sourceMessageIds: ['current'],
          ),
        ],
      );
      repository.replies.addAll([
        const ChatDoneEvent(
          answer: 'ถามกลับ',
          context: chatContext,
          questions: [question],
        ),
        const ChatDoneEvent(answer: 'ช้อย', context: corrected),
        const ChatDoneEvent(answer: 'พิมพ์', context: corrected),
        const ChatDoneEvent(answer: 'ข้าม', context: corrected),
        const ChatDoneEvent(answer: 'แก้คำตอบ', context: corrected),
        const ChatDoneEvent(
          answer: 'ข้อมูลแอป',
          context: ChatSessionContext(
            sessionId: 'current-chat',
            userGoal: 'ข้อมูลแอป',
          ),
        ),
        const ChatDoneEvent(
          answer: 'ต่อเรื่องใหม่',
          context: ChatSessionContext(
            sessionId: 'current-chat',
            userGoal: 'ข้อมูลแอป',
          ),
        ),
      ]);
      await submit(bloc, const ChatbotMessageSubmitted('เริ่ม'));
      expect(repository.requests.first.context, isNull);
      await submit(
        bloc,
        const ChatbotMessageSubmitted(
          'ช้อย',
          questionnaireAnswers: [
            QuestionnaireAnswer(questionId: 'batch:usage', optionId: 'outdoor'),
          ],
        ),
      );
      expect(repository.requests[1].context, chatContext);
      expect(repository.requests[1].answers.single.optionId, 'outdoor');
      expect(
        bloc.state.messages[1].questions.single.selectedOptionId,
        'outdoor',
      );
      await submit(
        bloc,
        const ChatbotMessageSubmitted(
          'พิมพ์',
          questionnaireAnswers: [
            QuestionnaireAnswer(questionId: 'batch:usage', text: 'ริมน้ำ'),
          ],
        ),
      );
      expect(repository.requests[2].answers.single.text, 'ริมน้ำ');
      await submit(
        bloc,
        const ChatbotMessageSubmitted('บางข้อ', questionnaireSkipped: true),
      );
      expect(repository.requests[3].skipped, isTrue);
      await submit(
        bloc,
        const ChatbotMessageEdited(index: 2, content: 'แก้งบ 900'),
      );
      expect(repository.requests[4].context, chatContext);
      expect(repository.requests[4].history.length, 2);
      expect(repository.requests[4].answers, isEmpty);
      await submit(bloc, const ChatbotMessageSubmitted('เปลี่ยนเรื่อง'));
      await submit(bloc, const ChatbotMessageSubmitted('ถามเรื่องแอปต่อ'));
      expect(repository.requests.last.context!.knownFacts, isEmpty);
      expect(repository.requests.last.context!.questions, isEmpty);
    },
  );

  test('a new chat cannot inherit another chat session', () async {
    final first = RecordingRepository()
      ..replies.add(const ChatDoneEvent(answer: 'หนึ่ง', context: chatContext));
    final second = RecordingRepository()
      ..replies.add(const ChatDoneEvent(answer: 'สอง'));
    final a = ChatbotBloc(sendMessage: SendChatMessageUseCase(first));
    final b = ChatbotBloc(sendMessage: SendChatMessageUseCase(second));
    addTearDown(a.close);
    addTearDown(b.close);
    await submit(a, const ChatbotMessageSubmitted('หนึ่ง'));
    await submit(b, const ChatbotMessageSubmitted('สอง'));
    expect(second.requests.single.context, isNull);
    expect(
      first.requests.single.sessionId,
      isNot(second.requests.single.sessionId),
    );
  });

  testWidgets('option index carries ID even when labels are equal', (
    tester,
  ) async {
    List<QuestionnaireAnswer>? answers;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            questions: const [question],
            onCompleted: (_) {},
            onDismiss: () {},
            onCompletedWithContext: (_, result, skipped) {
              answers = result;
              expect(skipped, isFalse);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('ช้อยชื่อเดียวกัน').last);
    await tester.pump(const Duration(milliseconds: 181));
    expect(answers!.single.optionId, 'outdoor');
    expect(answers!.single.text, isNull);
  });

  testWidgets('partial skip carries answered IDs plus an explicit skip flag', (
    tester,
  ) async {
    List<QuestionnaireAnswer>? answers;
    bool? skipped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveQuestionnaireCard(
            questions: [
              question,
              question.copyWith(id: 'batch:second'),
            ],
            onCompleted: (_) {},
            onDismiss: () {},
            onCompletedWithContext: (_, result, skip) {
              answers = result;
              skipped = skip;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('ช้อยชื่อเดียวกัน').last);
    await tester.pump(const Duration(milliseconds: 161));
    await tester.tap(find.byKey(const Key('chatbot-questionnaire-skip')));
    expect(answers!.single.questionId, 'batch:usage');
    expect(answers!.single.optionId, 'outdoor');
    expect(skipped, isTrue);
  });

  testWidgets(
    'cards use validated IDs and catalog names without reading answer text',
    (tester) async {
      const item = RecommendedItem(
        id: 27,
        name: 'ชื่อจริงจากคลัง',
        price: 17,
        unit: 'ชั่วโมง',
        imageUrl: '',
        status: 'available',
        category: 'ภาพ',
        description: 'รายละเอียด',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatMessageBubble(
                message: const ChatMessage(
                  role: ChatMessageRole.assistant,
                  content: 'ดูรายการในการ์ด',
                  recommendedItems: [item],
                ),
                onRentPressed: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommended-item-27')), findsOneWidget);
      expect(find.text('ชื่อจริงจากคลัง'), findsOneWidget);
    },
  );
}
