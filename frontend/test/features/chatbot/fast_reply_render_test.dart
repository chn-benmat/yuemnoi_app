import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_turn_timing.dart';
import 'package:frontend/features/chatbot/domain/repositories/chatbot_repository.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/pages/chat_bot.dart';

const understanding = ChatUnderstanding(
  requestScope: 'specific',
  informationSufficient: true,
  nextAction: 'answer',
  responseFlow: 'equipment',
);

class FastRepository implements ChatbotRepository {
  final controller = StreamController<ChatStreamEvent>.broadcast();
  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) => controller.stream;
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
  for (final questions in [false, true]) {
    testWidgets(
      'full render waits for done and paints ${questions ? "questionnaire" : "card"} immediately',
      (tester) async {
        final repository = FastRepository();
        final measurements = <ChatTimingMeasurement>[];
        final bloc = ChatbotBloc(
          sendMessage: SendChatMessageUseCase(repository),
          onTimingMeasured: measurements.add,
        );
        addTearDown(() {
          unawaited(bloc.close());
          unawaited(repository.controller.close());
        });
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(value: bloc, child: const ChatBotScreen()),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('chatbot-message-field')),
          'คำถาม',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chatbot-send-button')));
        await tester.pump();
        const item = RecommendedItem(
          id: 27,
          name: 'รายการจริงจากผลทดสอบ',
          price: 17,
          unit: 'ชั่วโมง',
          imageUrl: '',
          status: 'available',
          category: 'ภาพ',
          description: 'รายละเอียด',
        );
        const question = ClarificationQuestion(
          id: 'q:1',
          title: 'งานที่ต้องการ',
          options: ['งานหนึ่ง', 'งานสอง'],
          choices: [
            QuestionChoice(id: 'a', label: 'งานหนึ่ง', actionValue: 'one'),
            QuestionChoice(id: 'b', label: 'งานสอง', actionValue: 'two'),
          ],
        );
        final resultUnderstanding = questions
            ? const ChatUnderstanding(
                requestScope: 'broad',
                informationSufficient: false,
                nextAction: 'clarify',
                responseFlow: 'general',
              )
            : understanding;
        repository.controller.add(
          ChatMetadataEvent(
            mode: 'recommendation',
            understanding: resultUnderstanding,
            recommendedItems: questions ? [] : [item],
            questions: questions ? [question] : [],
          ),
        );
        repository.controller.add(const ChatDeltaEvent(text: 'ข้อความส่วนแรก'));
        await tester.pump(const Duration(milliseconds: 70));
        expect(measurements, isEmpty);
        repository.controller.add(
          ChatDoneEvent(
            answer: 'คำตอบครบ ${'รายละเอียด ' * 100}',
            understanding: resultUnderstanding,
            recommendedItems: questions ? [] : [item],
            questions: questions ? [question] : [],
          ),
        );
        unawaited(repository.controller.close());
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(measurements, hasLength(1));
        final measurement = measurements.single;
        expect(measurement.origin, 'flutter_interaction');
        expect(measurement.outcome, 'success');
        expect(
          measurement.completeRender,
          greaterThanOrEqualTo(measurement.transportComplete!),
        );
        expect(bloc.state.messages.last.understanding, resultUnderstanding);
        expect(bloc.state.messages.last.content, startsWith('คำตอบครบ'));
        if (questions) {
          expect(
            find.byKey(const Key('chatbot-questionnaire-card')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('recommended-item-27')),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(const ValueKey('recommended-item-27')),
            findsOneWidget,
          );
        }
        await tester.pump(const Duration(seconds: 1));
        expect(measurements, hasLength(1));
      },
    );
  }
  test(
    'failed and cancelled requests cannot produce success render samples',
    () {
      for (final outcome in ['error', 'cancelled', 'render_not_observed']) {
        final timing = ChatTurnTiming();
        final failure = timing.finish(turnId: 'test', outcome: outcome)!;
        expect(failure.completeRender, isNull);
        expect(
          timing.finish(turnId: 'test', outcome: 'success', rendered: true),
          isNull,
        );
      }
    },
  );
}
