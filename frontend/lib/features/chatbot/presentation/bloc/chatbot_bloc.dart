import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chatbot_failure.dart';
import '../../domain/entities/chat_turn_timing.dart';
import '../../domain/repositories/chatbot_repository.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import '../widgets/chat_response_label.dart';
import 'chatbot_event.dart';
import 'chatbot_state.dart';

class ChatbotBloc extends Bloc<ChatbotEvent, ChatbotState> {
  static const _streamUpdateInterval = Duration(
    milliseconds: int.fromEnvironment(
      'AI_CHAT_STREAM_UPDATE_MILLISECONDS',
      defaultValue: 50,
    ),
  );

  ChatbotBloc({
    required SendChatMessageUseCase sendMessage,
    DateTime Function()? now,
    this.onTimingMeasured,
    this.timingDiagnostics = const bool.fromEnvironment(
      'AI_CHAT_TIMING_DIAGNOSTICS',
    ),
    this.responseReadyTimeout = const Duration(
      seconds: int.fromEnvironment(
        'AI_CHAT_RESPONSE_READY_TIMEOUT_SECONDS',
        defaultValue: 30,
      ),
    ),
  }) : _sendMessage = sendMessage,
       _now = now ?? DateTime.now,
       super(ChatbotState.initial()) {
    on<ChatbotMessageSubmitted>(_onMessageSubmitted);
    on<ChatbotMessageEdited>(_onMessageEdited);
    on<ChatbotRetryRequested>(_onRetryRequested);
    on<ChatbotStreamStopped>(_onStreamStopped);
    on<ChatbotResponseRendered>(_onResponseRendered);
  }

  final SendChatMessageUseCase _sendMessage;
  final DateTime Function() _now;
  _ChatbotRequestSnapshot? _retrySnapshot;
  int _attemptId = 0;
  final void Function(ChatTimingMeasurement)? onTimingMeasured;
  final bool timingDiagnostics;
  final Duration responseReadyTimeout;
  ChatTurnTiming? _turnTiming;
  String? _timingMessageId;

  void _finishTiming(String outcome, {bool rendered = false}) {
    final messages = state.messages.where((m) => m.id == _timingMessageId);
    final measurement = _turnTiming?.finish(
      turnId: _timingMessageId ?? '',
      outcome: outcome,
      rendered: rendered,
      responseFlow: messages.isEmpty
          ? null
          : messages.first.understanding?.responseFlow,
    );
    if (measurement != null) {
      onTimingMeasured?.call(measurement);
      // เปิดเฉพาะ debug ที่ขอวัดเวลา โดยไม่บันทึกข้อความหรือข้อมูลบัญชีผู้ใช้
      if (kDebugMode && timingDiagnostics) {
        debugPrint('CHAT_TIMING ${jsonEncode(measurement.toJson())}');
      }
    }
  }

  void _onResponseRendered(
    ChatbotResponseRendered event,
    Emitter<ChatbotState> emit,
  ) {
    if (event.messageId != _timingMessageId ||
        state.isSending ||
        state.errorMessage != null ||
        _turnTiming?.transportComplete == null) {
      return;
    }
    _finishTiming('success', rendered: true);
  }

  final String _sessionId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  void Function()? _activeStreamCanceller;
  bool _isStoppedByUser = false;

  void _onStreamStopped(
    ChatbotStreamStopped event,
    Emitter<ChatbotState> emit,
  ) {
    if (!state.isSending) return;
    _isStoppedByUser = true;
    _finishTiming('cancelled');
    _activeStreamCanceller?.call();
    _activeStreamCanceller = null;
  }

  Stream<ChatStreamEvent> _bufferChatDeltas(
    Stream<ChatStreamEvent> source,
    int attempt,
  ) {
    final turnTiming = _turnTiming;
    late final StreamController<ChatStreamEvent> controller;
    StreamSubscription<ChatStreamEvent>? subscription;
    Timer? flushTimer;
    Timer? readyTimer;
    var sourceFinished = false;
    final deltaBuffer = StringBuffer();

    void flushDeltas() {
      if (deltaBuffer.isEmpty || controller.isClosed) return;
      final text = deltaBuffer.toString();
      deltaBuffer.clear();
      controller.add(ChatDeltaEvent(text: text));
    }

    void stopTimer() {
      flushTimer?.cancel();
      flushTimer = null;
    }

    void stopReadyTimer() {
      readyTimer?.cancel();
      readyTimer = null;
    }

    void failReadyDeadline() {
      if (sourceFinished || attempt != _attemptId) return;
      sourceFinished = true;
      stopTimer();
      stopReadyTimer();
      deltaBuffer.clear();
      controller.addError(
        const ChatbotException(
          'ยืมหน่อย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง',
        ),
      );
      unawaited(subscription?.cancel());
      unawaited(controller.close());
    }

    void cancelActiveStream() {
      if (sourceFinished || attempt != _attemptId) return;
      sourceFinished = true;
      stopTimer();
      stopReadyTimer();
      flushDeltas();
      subscription?.cancel();
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller = StreamController<ChatStreamEvent>(
      onListen: () {
        _activeStreamCanceller = cancelActiveStream;
        // นับจาก interaction ที่ส่งคำขอ รวมเวลารอเครือข่ายก่อน headers
        final remaining =
            responseReadyTimeout - (turnTiming?.elapsed ?? Duration.zero);
        readyTimer = Timer(
          remaining.isNegative ? Duration.zero : remaining,
          failReadyDeadline,
        );
        flushTimer = Timer.periodic(
          _streamUpdateInterval,
          (_) => flushDeltas(),
        );
        subscription = source.listen(
          (event) {
            if (sourceFinished || attempt != _attemptId) return;
            if (event is ChatReadyEvent || event is ChatDoneEvent) {
              if (turnTiming?.responseReady == null &&
                  (turnTiming?.elapsed ?? Duration.zero) >
                      responseReadyTimeout) {
                failReadyDeadline();
                return;
              }
              turnTiming?.markResponseReady();
              stopReadyTimer();
            }
            if (event case ChatDeltaEvent(:final text)) {
              deltaBuffer.write(text);
              return;
            }

            flushDeltas();
            if (event is ChatDoneEvent) stopTimer();
            controller.add(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (sourceFinished || attempt != _attemptId) return;
            sourceFinished = true;
            stopTimer();
            stopReadyTimer();
            flushDeltas();
            if (attempt == _attemptId) _activeStreamCanceller = null;
            controller.addError(error, stackTrace);
            controller.close();
          },
          onDone: () {
            if (sourceFinished || attempt != _attemptId) return;
            sourceFinished = true;
            stopTimer();
            stopReadyTimer();
            flushDeltas();
            if (attempt == _attemptId) _activeStreamCanceller = null;
            controller.close();
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        stopTimer();
        stopReadyTimer();
        if (attempt == _attemptId) _activeStreamCanceller = null;
        if (!sourceFinished) {
          await subscription?.cancel();
        }
      },
    );

    return controller.stream;
  }

  Future<void> _handleMessageStream({
    required String query,
    required List<ChatMessage> history,
    required List<ChatMessage> messagesWithUser,
    required Emitter<ChatbotState> emit,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
    ChatTurnTiming? timing,
    _ChatbotRequestSnapshot? snapshotOverride,
  }) async {
    _activeStreamCanceller?.call();
    _activeStreamCanceller = null;
    _isStoppedByUser = false;
    final attempt = ++_attemptId;
    _finishTiming('render_not_observed');
    _turnTiming = timing ?? ChatTurnTiming(origin: 'bloc_submission');
    final startTime = _now();
    final messageId = 'msg_${startTime.microsecondsSinceEpoch}_$attempt';
    _timingMessageId = messageId;
    final contexts = history.reversed.where(
      (m) => m.role == ChatMessageRole.assistant && m.context != null,
    );
    final chatContext = contexts.isEmpty ? null : contexts.first.context;
    // เก็บคำขอที่จัดบริบทเรียบร้อยแล้ว เพื่อส่งซ้ำโดยไม่สร้างข้อความผู้ใช้ใหม่
    final request =
        snapshotOverride ??
        _ChatbotRequestSnapshot(
          query: query,
          history: List.unmodifiable(history.where((m) => !m.isFailure)),
          messagesWithUser: List.unmodifiable(messagesWithUser),
          sessionId: chatContext?.sessionId ?? _sessionId,
          context: chatContext,
          questionnaireAnswers: List.unmodifiable(
            chatContext == null
                ? const <QuestionnaireAnswer>[]
                : questionnaireAnswers,
          ),
          questionnaireSkipped: questionnaireSkipped,
          activeQuestionId:
              chatContext?.questions.any((q) => q.id == activeQuestionId) ==
                  true
              ? activeQuestionId
              : null,
        );
    _retrySnapshot = request;
    emit(
      state.copyWith(
        messages: [
          ...request.messagesWithUser,
          ChatMessage(
            id: messageId,
            role: ChatMessageRole.assistant,
            content: '',
            userQuery: request.query,
            isStreaming: true,
            createdAt: startTime,
            statusMessage: 'กำลังเชื่อมต่อยืมหน่อย AI',
          ),
        ],
        isSending: true,
        clearError: true,
        clearFailure: true,
        requestStartTime: startTime,
        currentStatusMessage: 'กำลังเชื่อมต่อยืมหน่อย AI',
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      await emit.forEach<ChatStreamEvent>(
        _bufferChatDeltas(
          _sendMessage.executeStream(
            query: request.query,
            history: request.history,
            sessionId: request.sessionId,
            context: request.context,
            questionnaireAnswers: request.questionnaireAnswers,
            questionnaireSkipped: request.questionnaireSkipped,
            activeQuestionId: request.activeQuestionId,
          ),
          attempt,
        ),
        onData: (event) {
          if (attempt != _attemptId || isClosed) return state;
          final currentMessages = List<ChatMessage>.from(state.messages);
          if (currentMessages.isEmpty) return state;
          final lastIndex = currentMessages.length - 1;
          final last = currentMessages[lastIndex];
          if (last.role != ChatMessageRole.assistant || last.id != messageId) {
            return state;
          }

          switch (event) {
            case ChatReadyEvent():
              currentMessages[lastIndex] = last.copyWith(
                responseDuration: _turnTiming?.responseReady,
              );
              return state.copyWith(messages: currentMessages);
            case ChatStatusEvent(:final message):
              final updatedActivities = List<String>.from(last.activities);
              if (!updatedActivities.contains(message)) {
                updatedActivities.add(message);
              }
              currentMessages[lastIndex] = last.copyWith(
                statusMessage: message,
                activities: updatedActivities,
              );
              return state.copyWith(
                messages: currentMessages,
                currentStatusMessage: message,
              );
            case ChatMetadataEvent(
              :final recommendedItems,
              :final questions,
              :final understanding,
            ):
              final effectiveQuestions = questions.isNotEmpty
                  ? questions
                  : last.questions;
              final effectiveRecommended = effectiveQuestions.isNotEmpty
                  ? const <RecommendedItem>[]
                  : (recommendedItems.isNotEmpty
                        ? recommendedItems
                        : last.recommendedItems);
              currentMessages[lastIndex] = last.copyWith(
                recommendedItems: effectiveRecommended,
                questions: effectiveQuestions,
                understanding: understanding,
              );
              return state.copyWith(messages: currentMessages);
            case ChatDeltaEvent(:final text):
              final isFirstDelta = last.content.isEmpty && text.isNotEmpty;
              if (isFirstDelta) _turnTiming?.markFirstText();
              final updatedDuration = isFirstDelta
                  ? (last.responseDuration ??
                        (stopwatch.elapsed.inMilliseconds > 0
                            ? stopwatch.elapsed
                            : const Duration(seconds: 1)))
                  : last.responseDuration;
              final dynamicStatus = chatResponseLabel(
                last.understanding?.responseKind,
                hasQuestions: last.questions.isNotEmpty,
              );
              currentMessages[lastIndex] = last.copyWith(
                content: last.content + text,
                responseDuration: updatedDuration,
                statusMessage: isFirstDelta
                    ? dynamicStatus
                    : last.statusMessage,
              );
              return state.copyWith(messages: currentMessages);
            case ChatDoneEvent(
              :final answer,
              :final suggestedReplies,
              :final recommendedItems,
              :final questions,
              :final searchSources,
              :final searchQuery,
              :final activities,
              :final context,
              :final references,
              :final understanding,
            ):
              stopwatch.stop();
              _retrySnapshot = null;
              _turnTiming?.markTransportComplete();
              final effectiveQuestions = understanding != null
                  ? questions
                  : (questions.isNotEmpty ? questions : last.questions);
              final effectiveRecommended = effectiveQuestions.isNotEmpty
                  ? const <RecommendedItem>[]
                  : recommendedItems;
              final effectiveContent = answer?.trim().isNotEmpty == true
                  ? answer!.trim()
                  : last.content;
              final effectiveActivities = activities.isNotEmpty
                  ? activities
                  : last.activities;
              final effectiveDuration =
                  _turnTiming?.responseReady ??
                  _turnTiming?.transportComplete ??
                  stopwatch.elapsed;
              final finalStatus = chatResponseLabel(
                (understanding ?? last.understanding)?.responseKind,
                hasQuestions: effectiveQuestions.isNotEmpty,
              );
              currentMessages[lastIndex] = last.copyWith(
                content: effectiveContent.isEmpty
                    ? 'การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่อีกครั้ง'
                    : effectiveContent,
                recommendedItems: effectiveRecommended,
                questions: effectiveQuestions,
                suggestedReplies: suggestedReplies,
                searchSources: searchSources,
                searchQuery: searchQuery,
                activities: effectiveActivities,
                context: context,
                understanding: understanding,
                references: references,
                isStreaming: false,
                responseDuration: effectiveDuration,
                statusMessage: finalStatus,
              );
              return state.copyWith(
                messages: currentMessages,
                isSending: false,
                clearError: true,
                clearFailure: true,
                clearStatus: true,
                clearStartTime: true,
              );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (attempt != _attemptId || isClosed) return state;
          stopwatch.stop();
          if (_isStoppedByUser) return _stoppedState(stopwatch.elapsed);
          return _failedState(error, stopwatch.elapsed, messageId);
        },
      );
      if (attempt != _attemptId || isClosed || emit.isDone) return;
      stopwatch.stop();
      if (_isStoppedByUser) {
        emit(_stoppedState(stopwatch.elapsed));
      } else if (state.isSending) {
        emit(
          _failedState(
            const ChatbotException('การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่อีกครั้ง'),
            stopwatch.elapsed,
            messageId,
          ),
        );
      }
    } catch (error) {
      if (attempt != _attemptId || isClosed || emit.isDone) return;
      stopwatch.stop();
      emit(
        _isStoppedByUser
            ? _stoppedState(stopwatch.elapsed)
            : _failedState(error, stopwatch.elapsed, messageId),
      );
    }
  }

  ChatbotState _stoppedState(Duration duration) {
    _retrySnapshot = null;
    _finishTiming('cancelled');
    final messages = List<ChatMessage>.from(state.messages);
    if (messages.isNotEmpty &&
        messages.last.role == ChatMessageRole.assistant) {
      final last = messages.last;
      messages[messages.length - 1] = last.copyWith(
        content: last.content.isEmpty ? 'หยุดการตอบกลับแล้ว' : last.content,
        isStreaming: false,
        responseDuration: last.responseDuration ?? duration,
        recommendedItems: const [],
        questions: const [],
        statusMessage: 'หยุดการตอบกลับแล้ว',
      );
    }
    return state.copyWith(
      messages: messages,
      isSending: false,
      clearError: true,
      clearFailure: true,
      clearStatus: true,
      clearStartTime: true,
    );
  }

  ChatbotState _failedState(Object error, Duration duration, String messageId) {
    _finishTiming('error');
    final exception = error is ChatbotException
        ? error
        : const ChatbotException('เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง');
    final status = exception.statusCode;
    final seconds = exception.retryAfterSeconds;
    final temporaryQuota =
        exception.errorCode == 'quota_temporarily_unavailable' ||
        exception.errorCode == 'providers_rate_limited' ||
        (status == 429 && exception.errorCode != 'quota_exhausted');
    // พักปุ่มโควต้าชั่วคราวอย่างน้อย 1 นาที และคงเวลาที่บริการขอหากนานกว่า
    final retrySeconds = temporaryQuota && (seconds ?? 0) < 60 ? 60 : seconds;
    final failure = ChatbotFailure(
      messageId: messageId,
      message: exception.message,
      errorCode: exception.errorCode,
      statusCode: status,
      isRetryable:
          status == null || status == 408 || status == 429 || status >= 500,
      retryAvailableAt: retrySeconds != null && retrySeconds > 0
          ? _now().add(Duration(seconds: retrySeconds))
          : null,
    );
    final messages = List<ChatMessage>.from(state.messages);
    if (messages.isNotEmpty && messages.last.id == messageId) {
      final last = messages.last;
      // ผลที่ล้มเหลวไม่แสดงรายการหรือคำถามที่ยังไม่ได้ยืนยันจาก done
      messages[messages.length - 1] = ChatMessage(
        id: last.id,
        role: ChatMessageRole.assistant,
        content: exception.message,
        userQuery: last.userQuery,
        createdAt: last.createdAt,
        responseDuration: duration,
        statusMessage: 'คำขอไม่สำเร็จ',
        isFailure: true,
      );
    }
    return state.copyWith(
      messages: messages,
      isSending: false,
      errorMessage: exception.message,
      failure: failure,
      clearStatus: true,
      clearStartTime: true,
    );
  }

  Future<void> _onRetryRequested(
    ChatbotRetryRequested event,
    Emitter<ChatbotState> emit,
  ) async {
    final failure = state.failure;
    final request = _retrySnapshot;
    if (state.isSending ||
        request == null ||
        failure == null ||
        failure.messageId != event.messageId ||
        !failure.canRetry(_now()) ||
        state.messages.isEmpty ||
        state.messages.last.id != event.messageId) {
      return;
    }
    await _handleMessageStream(
      query: request.query,
      history: request.history,
      messagesWithUser: request.messagesWithUser,
      snapshotOverride: request,
      timing: event.timing,
      emit: emit,
    );
  }

  Future<void> _onMessageEdited(
    ChatbotMessageEdited event,
    Emitter<ChatbotState> emit,
  ) async {
    final content = event.content.trim();
    if (content.isEmpty ||
        state.isSending ||
        event.index < 0 ||
        event.index >= state.messages.length ||
        state.messages[event.index].role != ChatMessageRole.user) {
      return;
    }

    final history = state.messages.take(event.index).toList(growable: false);
    final messagesWithEditedQuestion = [
      ...history,
      ChatMessage(role: ChatMessageRole.user, content: content),
    ];

    await _handleMessageStream(
      query: content,
      history: history,
      messagesWithUser: messagesWithEditedQuestion,
      timing: event.timing,
      emit: emit,
    );
  }

  Future<void> _onMessageSubmitted(
    ChatbotMessageSubmitted event,
    Emitter<ChatbotState> emit,
  ) async {
    final query = event.query.trim();
    if (query.isEmpty || state.isSending) return;

    final history = List<ChatMessage>.from(state.messages);
    if (history.isNotEmpty &&
        history.last.role == ChatMessageRole.assistant &&
        history.last.questions.isNotEmpty) {
      final lastAssistant = history.last;
      final updatedQuestions = lastAssistant.questions
          .map((q) {
            final selected = event.selectedOptions[q.id];
            final answers = event.questionnaireAnswers.where(
              (a) => a.questionId == q.id,
            );
            final answer = answers.isEmpty ? null : answers.first;
            final choices = q.choices.where((c) => c.id == answer?.optionId);
            final label = choices.isEmpty
                ? answer?.text ?? selected
                : choices.first.label;
            return label == null
                ? q
                : q.copyWith(
                    title:
                        q.branchTitles?[event.questionnaireAnswers
                            .where((a) => a.questionId == q.branchQuestionId)
                            .firstOrNull
                            ?.optionId] ??
                        q.title,
                    selectedOption: label,
                    selectedOptionId: answer?.optionId,
                  );
          })
          .toList(growable: false);
      history[history.length - 1] = lastAssistant.copyWith(
        questions: updatedQuestions,
      );
    }

    final messagesWithQuestion = [
      ...history,
      ChatMessage(
        role: ChatMessageRole.user,
        content: query,
        isVisibleInChat: event.isVisibleInChat,
      ),
    ];

    final contexts = history.reversed.where(
      (m) => m.role == ChatMessageRole.assistant && m.context != null,
    );
    final latestContext = contexts.isEmpty ? null : contexts.first.context;
    final pending = state.failure == null ? null : _retrySnapshot;
    // คำตอบที่ผู้ใช้เลือกยังเป็นหลักฐาน แม้รอบก่อนล้มเหลวและพิมพ์ข้อความต่อ
    final answers =
        event.questionnaireAnswers.isEmpty &&
            pending?.context != null &&
            pending!.context == latestContext
        ? pending.questionnaireAnswers
        : event.questionnaireAnswers;

    await _handleMessageStream(
      query: query,
      history: history,
      messagesWithUser: messagesWithQuestion,
      questionnaireAnswers: answers,
      questionnaireSkipped: event.questionnaireSkipped,
      activeQuestionId: event.activeQuestionId,
      timing: event.timing,
      emit: emit,
    );
  }

  @override
  Future<void> close() {
    _finishTiming('screen_closed');
    _activeStreamCanceller?.call();
    _activeStreamCanceller = null;
    _attemptId++;
    _retrySnapshot = null;
    _sendMessage.close();
    return super.close();
  }
}

// สำเนาคำขอของรอบล่าสุด ไม่เผย history หรือ context ไปยัง widget
class _ChatbotRequestSnapshot {
  const _ChatbotRequestSnapshot({
    required this.query,
    required this.history,
    required this.messagesWithUser,
    required this.sessionId,
    required this.context,
    required this.questionnaireAnswers,
    required this.questionnaireSkipped,
    required this.activeQuestionId,
  });
  final String query;
  final List<ChatMessage> history;
  final List<ChatMessage> messagesWithUser;
  final String sessionId;
  final ChatSessionContext? context;
  final List<QuestionnaireAnswer> questionnaireAnswers;
  final bool questionnaireSkipped;
  final String? activeQuestionId;
}
