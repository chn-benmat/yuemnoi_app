import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_turn_timing.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_event.dart';
import 'package:mocktail/mocktail.dart';

import 'fast_reply_render_test.dart' show FastRepository;

class _Client extends Mock implements ApiClient {}

void main() {
  test(
    'production default gives every message a 30 second ready budget',
    () async {
      final repository = FastRepository();
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      expect(bloc.responseReadyTimeout, const Duration(seconds: 30));
      await bloc.close();
      await repository.controller.close();
    },
  );

  testWidgets('ready stops the budget before later SSE and rendering', (
    tester,
  ) async {
    final repository = FastRepository();
    final timing = ChatTurnTiming();
    final bloc = ChatbotBloc(
      sendMessage: SendChatMessageUseCase(repository),
      responseReadyTimeout: const Duration(seconds: 1),
    );
    addTearDown(() {
      unawaited(bloc.close());
      unawaited(repository.controller.close());
    });
    bloc.add(ChatbotMessageSubmitted('คำถาม', timing: timing));
    await tester.pump();
    repository.controller.add(
      const ChatReadyEvent(response: ChatResponse(answer: 'คำตอบครบ')),
    );
    await tester.pump();
    final ready = timing.responseReady;
    expect(ready, isNotNull);
    expect(bloc.state.messages.last.responseDuration, ready);
    await tester.pump(const Duration(seconds: 2));
    expect(bloc.state.errorMessage, isNull);
    repository.controller.add(const ChatDeltaEvent(text: 'คำตอบ'));
    repository.controller.add(const ChatDoneEvent(answer: 'คำตอบครบ'));
    await tester.pump();
    expect(bloc.state.isSending, isFalse);
    expect(bloc.state.messages.last.content, 'คำตอบครบ');
    expect(bloc.state.messages.last.responseDuration, ready);
    expect(timing.transportComplete, greaterThanOrEqualTo(ready!));
  });

  testWidgets('partial text and status do not extend ready deadline', (
    tester,
  ) async {
    final repository = FastRepository();
    var cancelled = false;
    repository.controller.onCancel = () => cancelled = true;
    final timing = ChatTurnTiming();
    final bloc = ChatbotBloc(
      sendMessage: SendChatMessageUseCase(repository),
      responseReadyTimeout: const Duration(seconds: 1),
    );
    addTearDown(() {
      unawaited(bloc.close());
      unawaited(repository.controller.close());
    });
    bloc.add(ChatbotMessageSubmitted('คำถาม', timing: timing));
    await tester.pump();
    repository.controller.add(
      const ChatStatusEvent(step: 'processing', message: 'กำลังประมวลผล'),
    );
    repository.controller.add(const ChatDeltaEvent(text: 'ยังไม่ครบ'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(timing.responseReady, isNull);
    expect(bloc.state.isSending, isFalse);
    expect(bloc.state.errorMessage, contains('นานเกินไป'));
    final failure = bloc.state.messages.last.content;
    repository.controller.add(
      const ChatReadyEvent(response: ChatResponse(answer: 'สายเกินไป')),
    );
    repository.controller.add(const ChatDoneEvent(answer: 'สายเกินไป'));
    await tester.pump();
    expect(bloc.state.messages.last.content, failure);
  });

  const payload = {
    'status': 'success',
    'answer': 'คำตอบครบ',
    'suggested_replies': ['ถามต่อ'],
  };
  for (final invalid in [false, true]) {
    test(
      'complete ready payload ${invalid ? 'rejects a changed done' : 'precedes deltas and identical done'}',
      () async {
        final client = _Client();
        when(
          () => client.postStream(any(), data: any(named: 'data')),
        ).thenAnswer(
          (_) async => Stream.fromIterable([
            'event: ready',
            'data: ${jsonEncode(payload)}',
            '',
            'event: delta',
            'data: ${jsonEncode({'text': 'คำ'})}',
            '',
            'event: done',
            'data: ${jsonEncode(invalid ? {...payload, 'answer': 'ถูกเปลี่ยน'} : payload)}',
            '',
          ]),
        );
        final source = ChatbotRemoteDataSource(client: client);
        final events = <ChatStreamEvent>[];
        final result = source
            .sendMessageStream(query: 'คำถาม', history: [])
            .toList()
            .then(events.addAll);
        if (invalid) {
          await expectLater(result, throwsA(isA<ChatbotRemoteException>()));
        } else {
          await result;
          expect((events.first as ChatReadyEvent).response.answer, 'คำตอบครบ');
          expect((events.first as ChatReadyEvent).response.suggestedReplies, [
            'ถามต่อ',
          ]);
          expect(events[1], isA<ChatDeltaEvent>());
          expect(events.last, isA<ChatDoneEvent>());
        }
      },
    );
  }
}
