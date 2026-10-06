import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_message.dart';
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
       super(ChatbotState.initial()) {
    on<ChatbotMessageSubmitted>(_onMessageSubmitted);
    on<ChatbotMessageEdited>(_onMessageEdited);
    on<ChatbotStreamStopped>(_onStreamStopped);
    on<ChatbotResponseRendered>(_onResponseRendered);
  }

  final SendChatMessageUseCase _sendMessage;
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

  Stream<ChatStreamEvent> _bufferChatDeltas(Stream<ChatStreamEvent> source) {
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
      if (sourceFinished) return;
      sourceFinished = true;
      stopTimer();
      stopReadyTimer();
      deltaBuffer.clear();
      controller.addError(
        const ChatbotException(
          'ผู้ช่วย AI ใช้เวลาตอบนานเกินไป กรุณาลองใหม่อีกครั้ง',
        ),
      );
      unawaited(subscription?.cancel());
      unawaited(controller.close());
    }

    void cancelActiveStream() {
      if (sourceFinished) return;
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
            responseReadyTimeout - (_turnTiming?.elapsed ?? Duration.zero);
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
            if (sourceFinished) return;
            if (event is ChatReadyEvent || event is ChatDoneEvent) {
              if (_turnTiming?.responseReady == null &&
                  (_turnTiming?.elapsed ?? Duration.zero) >
                      responseReadyTimeout) {
                failReadyDeadline();
                return;
              }
              _turnTiming?.markResponseReady();
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
            if (sourceFinished) return;
            sourceFinished = true;
            stopTimer();
            stopReadyTimer();
            flushDeltas();
            _activeStreamCanceller = null;
            controller.addError(error, stackTrace);
            controller.close();
          },
          onDone: () {
            if (sourceFinished) return;
            sourceFinished = true;
            stopTimer();
            stopReadyTimer();
            flushDeltas();
            _activeStreamCanceller = null;
            controller.close();
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        stopTimer();
        stopReadyTimer();
        _activeStreamCanceller = null;
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
  }) async {
    _activeStreamCanceller = null;
    _isStoppedByUser = false;

    _finishTiming('render_not_observed');
    _turnTiming = timing ?? ChatTurnTiming(origin: 'bloc_submission');
    final startTime = DateTime.now();
    final messageId =
        'msg_${startTime.millisecondsSinceEpoch}_${query.hashCode.abs()}';
    _timingMessageId = messageId;
    final placeholder = ChatMessage(
      id: messageId,
      role: ChatMessageRole.assistant,
      content: '',
      userQuery: query,
      isStreaming: true,
      createdAt: startTime,
      statusMessage: 'กำลังวิเคราะห์คำถาม...',
    );

    emit(
      state.copyWith(
        messages: [...messagesWithUser, placeholder],
        isSending: true,
        clearError: true,
        requestStartTime: startTime,
        currentStatusMessage: 'กำลังวิเคราะห์คำถาม...',
      ),
    );

    final stopwatch = Stopwatch()..start();
    // ย้อนบริบทตามประวัติที่ยังเหลืออยู่ เมื่อแก้ข้อความจะไม่ใช้ผลลัพธ์ในอนาคต
    final contexts = history.reversed.where(
      (m) => m.role == ChatMessageRole.assistant && m.context != null,
    );
    final chatContext = contexts.isEmpty ? null : contexts.first.context;
    try {
      await emit.forEach<ChatStreamEvent>(
        _bufferChatDeltas(
          _sendMessage.executeStream(
            query: query,
            history: history,
            sessionId: chatContext?.sessionId ?? _sessionId,
            context: chatContext,
            questionnaireAnswers: chatContext == null
                ? const []
                : questionnaireAnswers,
            questionnaireSkipped: questionnaireSkipped,
            activeQuestionId:
                chatContext?.questions.any((q) => q.id == activeQuestionId) ==
                    true
                ? activeQuestionId
                : null,
          ),
        ),
        onData: (event) {
          final currentMessages = List<ChatMessage>.from(state.messages);
          if (currentMessages.isEmpty) return state;
          final lastIndex = currentMessages.length - 1;
          final last = currentMessages[lastIndex];
          if (last.role != ChatMessageRole.assistant) return state;

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
                clearStatus: true,
                clearStartTime: true,
              );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          stopwatch.stop();
          _finishTiming(_isStoppedByUser ? 'cancelled' : 'error');
          if (_isStoppedByUser) {
            final currentMessages = List<ChatMessage>.from(state.messages);
            if (currentMessages.isNotEmpty &&
                currentMessages.last.role == ChatMessageRole.assistant) {
              final last = currentMessages.last;
              final duration =
                  last.responseDuration ??
                  (stopwatch.elapsed.inMilliseconds > 0
                      ? stopwatch.elapsed
                      : const Duration(seconds: 1));
              currentMessages[currentMessages.length - 1] = last.copyWith(
                content: last.content.isEmpty
                    ? 'หยุดการตอบกลับแล้ว'
                    : last.content,
                isStreaming: false,
                responseDuration: duration,
                statusMessage: 'สรุปคำแนะนำ',
              );
            }
            return state.copyWith(
              messages: currentMessages,
              isSending: false,
              clearError: true,
              clearStatus: true,
              clearStartTime: true,
            );
          }
          final errorMessage = error is ChatbotException
              ? error.message
              : 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
          final currentMessages = List<ChatMessage>.from(state.messages);
          if (currentMessages.isNotEmpty &&
              currentMessages.last.role == ChatMessageRole.assistant) {
            currentMessages[currentMessages.length - 1] = currentMessages.last
                .copyWith(
                  content: errorMessage,
                  isStreaming: false,
                  responseDuration: stopwatch.elapsed,
                  statusMessage: 'คำขอไม่สำเร็จ',
                );
          }
          return state.copyWith(
            messages: currentMessages,
            isSending: false,
            errorMessage: errorMessage,
            clearStatus: true,
            clearStartTime: true,
          );
        },
      );
      if (_isStoppedByUser) {
        stopwatch.stop();
        final currentMessages = List<ChatMessage>.from(state.messages);
        if (currentMessages.isNotEmpty &&
            currentMessages.last.role == ChatMessageRole.assistant) {
          final last = currentMessages.last;
          final duration =
              last.responseDuration ??
              (stopwatch.elapsed.inMilliseconds > 0
                  ? stopwatch.elapsed
                  : const Duration(seconds: 1));
          currentMessages[currentMessages.length - 1] = last.copyWith(
            content: last.content.isEmpty ? 'หยุดการตอบกลับแล้ว' : last.content,
            isStreaming: false,
            responseDuration: duration,
            statusMessage: 'สรุปคำแนะนำ',
          );
        }
        emit(
          state.copyWith(
            messages: currentMessages,
            isSending: false,
            clearError: true,
            clearStatus: true,
            clearStartTime: true,
          ),
        );
        return;
      }
      if (state.isSending) {
        stopwatch.stop();
        _finishTiming('incomplete');
        final currentMessages = List<ChatMessage>.from(state.messages);
        const errorMessage = 'การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่อีกครั้ง';
        if (currentMessages.isNotEmpty &&
            currentMessages.last.role == ChatMessageRole.assistant) {
          currentMessages[currentMessages.length - 1] = currentMessages.last
              .copyWith(
                content: errorMessage,
                isStreaming: false,
                responseDuration: stopwatch.elapsed,
                statusMessage: 'คำขอไม่สำเร็จ',
              );
        }
        emit(
          state.copyWith(
            messages: currentMessages,
            isSending: false,
            errorMessage: errorMessage,
            clearStatus: true,
            clearStartTime: true,
          ),
        );
      }
    } catch (_) {
      stopwatch.stop();
      _finishTiming(_isStoppedByUser ? 'cancelled' : 'error');
      if (_isStoppedByUser) {
        final currentMessages = List<ChatMessage>.from(state.messages);
        if (currentMessages.isNotEmpty &&
            currentMessages.last.role == ChatMessageRole.assistant) {
          final last = currentMessages.last;
          final duration =
              last.responseDuration ??
              (stopwatch.elapsed.inMilliseconds > 0
                  ? stopwatch.elapsed
                  : const Duration(seconds: 1));
          currentMessages[currentMessages.length - 1] = last.copyWith(
            content: last.content.isEmpty ? 'หยุดการตอบกลับแล้ว' : last.content,
            isStreaming: false,
            responseDuration: duration,
            statusMessage: 'สรุปคำแนะนำ',
          );
        }
        emit(
          state.copyWith(
            messages: currentMessages,
            isSending: false,
            clearError: true,
            clearStatus: true,
            clearStartTime: true,
          ),
        );
        return;
      }
      final currentMessages = List<ChatMessage>.from(state.messages);
      const errorMessage = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
      if (currentMessages.isNotEmpty &&
          currentMessages.last.role == ChatMessageRole.assistant) {
        currentMessages[currentMessages.length - 1] = currentMessages.last
            .copyWith(
              content: errorMessage,
              isStreaming: false,
              responseDuration: stopwatch.elapsed,
              statusMessage: 'คำขอไม่สำเร็จ',
            );
      }
      emit(
        state.copyWith(
          messages: currentMessages,
          isSending: false,
          errorMessage: errorMessage,
          clearStatus: true,
          clearStartTime: true,
        ),
      );
    }
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

    await _handleMessageStream(
      query: query,
      history: history,
      messagesWithUser: messagesWithQuestion,
      questionnaireAnswers: event.questionnaireAnswers,
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
    _sendMessage.close();
    return super.close();
  }
}
