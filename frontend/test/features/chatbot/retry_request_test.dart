import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/chatbot/data/datasources/chatbot_remote_data_source.dart';
import 'package:frontend/features/chatbot/data/repositories/chatbot_repository_impl.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';
import 'package:frontend/features/chatbot/domain/repositories/chatbot_repository.dart';
import 'package:frontend/features/chatbot/domain/usecases/send_chat_message_usecase.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_bloc.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_event.dart';
import 'package:frontend/features/chatbot/presentation/bloc/chatbot_state.dart';

const _question = ClarificationQuestion(
  id: 'usage',
  title: 'ใช้งานอะไร',
  options: ['ถ่ายภาพ', 'วิดีโอ'],
  choices: [
    QuestionChoice(id: 'photo', label: 'ถ่ายภาพ', actionValue: 'photo'),
    QuestionChoice(id: 'video', label: 'วิดีโอ', actionValue: 'video'),
  ],
);
const _context = ChatSessionContext(
  sessionId: 'chat-test',
  userGoal: 'หากล้อง',
  questions: [_question],
  budgetMax: 500,
  budgetUnit: 'วัน',
);
const _failure = ChatbotException('เครือข่ายขัดข้อง');

Future<ChatbotState> _act(ChatbotBloc bloc, ChatbotEvent event) {
  final completed = bloc.stream.firstWhere((s) => !s.isSending);
  bloc.add(event);
  return completed;
}

void main() {
  test(
    'retry replaces failure without duplicating user or leaking candidates',
    () async {
      final repository = _RecordingRepository([
        _candidateFailure(),
        const ChatDoneEvent(answer: 'คำตอบใหม่'),
      ]);
      final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
      addTearDown(bloc.close);
      final failed = await _act(bloc, const ChatbotMessageSubmitted('หากล้อง'));
      expect(failed.messages.last.recommendedItems, isEmpty);
      final completed = bloc.stream.firstWhere(
        (s) => !s.isSending && s.failure == null,
      );
      bloc.add(ChatbotRetryRequested(failed.failure!.messageId));
      bloc.add(ChatbotRetryRequested(failed.failure!.messageId));
      final result = await completed;
      expect(repository.requests, hasLength(2));
      expect(repository.requests[1], repository.requests[0]);
      expect(
        result.messages.where((m) => m.role == ChatMessageRole.user),
        hasLength(1),
      );
      expect(result.messages.last.content, 'คำตอบใหม่');
      expect(result.messages.last.recommendedItems, isEmpty);
    },
  );

  for (final hidden in [false, true]) {
    test(
      'retry preserves context and partial questionnaire IDs hidden=$hidden',
      () async {
        final repository = _RecordingRepository([
          const ChatDoneEvent(
            answer: 'ขอรายละเอียด',
            questions: [_question],
            context: _context,
          ),
          _failure,
          const ChatDoneEvent(answer: 'สำเร็จ'),
        ]);
        final bloc = ChatbotBloc(
          sendMessage: SendChatMessageUseCase(repository),
        );
        addTearDown(bloc.close);
        await _act(bloc, const ChatbotMessageSubmitted('หากล้อง'));
        final failed = await _act(
          bloc,
          ChatbotMessageSubmitted(
            'ถ่ายภาพ',
            isVisibleInChat: !hidden,
            activeQuestionId: 'usage',
            questionnaireSkipped: true,
            questionnaireAnswers: const [
              QuestionnaireAnswer(questionId: 'usage', optionId: 'photo'),
            ],
          ),
        );
        final count = failed.messages.length;
        final result = await _act(
          bloc,
          ChatbotRetryRequested(failed.failure!.messageId),
        );
        expect(repository.requests[2], repository.requests[1]);
        expect(repository.requests[2]['context'], _context);
        expect(repository.requests[2]['activeQuestionId'], 'usage');
        expect(repository.requests[2]['skipped'], true);
        expect(repository.requests[2]['answers'], const [
          QuestionnaireAnswer(questionId: 'usage', optionId: 'photo'),
        ]);
        expect(result.messages.length, count);
        expect(
          result.messages.where(
            (m) => m.role == ChatMessageRole.user && m.isVisibleInChat,
          ),
          hasLength(hidden ? 1 : 2),
        );
      },
    );
  }

  test('retry of edited turn preserves history before edit', () async {
    final repository = _RecordingRepository([
      const ChatDoneEvent(answer: 'เก่า', context: _context),
      _failure,
      const ChatDoneEvent(answer: 'ใหม่'),
    ]);
    final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
    addTearDown(bloc.close);
    await _act(bloc, const ChatbotMessageSubmitted('คำถามเก่า'));
    final failed = await _act(
      bloc,
      const ChatbotMessageEdited(index: 0, content: 'แก้คำถาม'),
    );
    await _act(bloc, ChatbotRetryRequested(failed.failure!.messageId));
    expect(repository.requests[2], repository.requests[1]);
    expect(repository.requests[2]['history'], isEmpty);
    expect(repository.requests[2]['context'], isNull);
    expect(bloc.state.messages.first.content, 'แก้คำถาม');
  });

  test(
    'quota deadline blocks early retries and allows a single retry when due',
    () async {
      var now = DateTime.utc(2026, 10, 6);
      final repository = _RecordingRepository([
        const ChatbotException(
          'รอโควตา',
          statusCode: 503,
          errorCode: 'providers_rate_limited',
          retryAfterSeconds: 5,
        ),
        const ChatDoneEvent(answer: 'สำเร็จ'),
      ]);
      final bloc = ChatbotBloc(
        sendMessage: SendChatMessageUseCase(repository),
        now: () => now,
      );
      addTearDown(bloc.close);
      final failed = await _act(bloc, const ChatbotMessageSubmitted('หากล้อง'));
      final retry = ChatbotRetryRequested(failed.failure!.messageId);
      bloc.add(retry);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests, hasLength(1));
      expect(
        failed.failure!.retryAvailableAt,
        now.add(const Duration(seconds: 5)),
      );
      now = now.add(const Duration(seconds: 5));
      await _act(bloc, retry);
      expect(repository.requests, hasLength(2));
    },
  );

  test(
    'HTTP and SSE quota metadata survives data and repository layers',
    () async {
      for (final http in [true, false]) {
        final source = ChatbotRepositoryImpl(
          ChatbotRemoteDataSource(client: _QuotaClient(http)),
        );
        await expectLater(
          source.sendMessageStream(query: 'หากล้อง', history: const []),
          emitsError(
            isA<ChatbotException>()
                .having((e) => e.errorCode, 'code', 'providers_rate_limited')
                .having((e) => e.retryAfterSeconds, 'wait', 5),
          ),
        );
        source.close();
      }
    },
  );

  test('new send invalidates old failure and stop cancels a retry', () async {
    final pending = StreamController<ChatStreamEvent>.broadcast();
    final repository = _RecordingRepository([
      _failure,
      pending.stream,
      const ChatDoneEvent(answer: 'คำตอบใหม่'),
    ]);
    final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
    addTearDown(() async {
      await bloc.close();
      await pending.close();
    });
    final failed = await _act(bloc, const ChatbotMessageSubmitted('หากล้อง'));
    final started = bloc.stream.firstWhere((s) => s.isSending);
    bloc.add(ChatbotRetryRequested(failed.failure!.messageId));
    await started;
    await _act(bloc, const ChatbotStreamStopped());
    expect(bloc.state.failure, isNull);
    pending.add(const ChatDeltaEvent(text: 'ข้อความจากรอบเก่า'));
    await _act(bloc, const ChatbotMessageSubmitted('คำถามใหม่'));
    bloc.add(ChatbotRetryRequested(failed.failure!.messageId));
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests, hasLength(3));
    expect(bloc.state.messages.last.content, 'คำตอบใหม่');
  });

  test('validation failure does not enable retry or invent a wait', () async {
    final repository = _RecordingRepository([
      const ChatbotException('แก้คำถาม', statusCode: 422),
    ]);
    final bloc = ChatbotBloc(sendMessage: SendChatMessageUseCase(repository));
    addTearDown(bloc.close);
    final failed = await _act(bloc, const ChatbotMessageSubmitted('คำถาม'));
    expect(failed.failure!.isRetryable, false);
    expect(failed.failure!.retryAvailableAt, isNull);
    bloc.add(ChatbotRetryRequested(failed.failure!.messageId));
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests, hasLength(1));
  });
}

class _RecordingRepository implements ChatbotRepository {
  _RecordingRepository(this.replies);
  final List<Object> replies;
  final requests = <Map<String, Object?>>[];
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
    requests.add({
      'query': query,
      'history': history,
      'sessionId': sessionId,
      'context': context,
      'answers': questionnaireAnswers,
      'skipped': questionnaireSkipped,
      'activeQuestionId': activeQuestionId,
    });
    final reply = replies.removeAt(0);
    if (reply is ChatbotException) throw reply;
    if (reply is Stream<ChatStreamEvent>) {
      yield* reply;
    } else {
      yield reply as ChatStreamEvent;
    }
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuotaClient implements ApiClient {
  _QuotaClient(this.http);
  final bool http;
  @override
  Future<Stream<String>> postStream(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    if (http)
      throw const ApiClientException(
        ApiClientErrorType.invalidResponse,
        statusCode: 503,
        errorCode: 'providers_rate_limited',
        retryAfterSeconds: 5,
      );
    return Stream.fromIterable([
      'event: error',
      'data: {"error_code":"providers_rate_limited","retry_after_seconds":5}',
      '',
    ]);
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Stream<ChatStreamEvent> _candidateFailure() async* {
  yield const ChatMetadataEvent(
    mode: 'recommendation',
    recommendedItems: [
      RecommendedItem(
        id: 1,
        name: 'candidate',
        price: 1,
        unit: 'วัน',
        imageUrl: '',
        status: null,
        category: null,
        description: null,
      ),
    ],
  );
  throw _failure;
}
