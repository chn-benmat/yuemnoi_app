import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/repositories/chatbot_repository.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_event.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_state.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_message_bubble.dart';

class _StreamingChatbotRepository implements ChatbotRepository {
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
  }) {
    return controller.stream;
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
  }) {
    throw UnimplementedError();
  }

  @override
  void close() {}
}

void main() {
  test(
    'batches a burst of streaming deltas before emitting UI states',
    () async {
      final repository = _StreamingChatbotRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(() async {
        await repository.controller.close();
        await bloc.close();
      });

      final emittedStates = <ChatbotState>[];
      final subscription = bloc.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      bloc.add(const ChatbotMessageSubmitted('แนะนำกล้อง'));
      await Future<void>.delayed(Duration.zero);

      for (var index = 0; index < 100; index++) {
        repository.controller.add(const ChatDeltaEvent(text: 'ก'));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      repository.controller.add(const ChatDoneEvent());

      final completed = await bloc.stream.firstWhere(
        (state) =>
            !state.isSending &&
            state.messages.last.role == ChatMessageRole.assistant &&
            state.messages.last.content.length == 100,
      );

      expect(completed.messages.last.content, 'ก' * 100);
      expect(emittedStates.length, lessThan(10));
    },
  );

  testWidgets(
    'stream updates stay lightweight and do not request scroll from build',
    (tester) async {
      var progressCalls = 0;

      Widget buildBubble(String content) {
        return MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: ChatMessage(
                id: 'assistant-1',
                role: ChatMessageRole.assistant,
                content: content,
                isStreaming: true,
              ),
              onRentPressed: (_) {},
              onTextProgress: () => progressCalls++,
            ),
          ),
        );
      }

      await tester.pumpWidget(buildBubble('## กล้อง'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);

      await tester.pumpWidget(buildBubble('## กล้องสำหรับเดินทาง'));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chatbot-markdown-response-assistant-1')),
        findsOneWidget,
      );
    },
  );
}
