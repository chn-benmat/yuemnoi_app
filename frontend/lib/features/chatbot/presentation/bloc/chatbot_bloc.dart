import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chatbot_repository.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import 'chatbot_event.dart';
import 'chatbot_state.dart';

class ChatbotBloc extends Bloc<ChatbotEvent, ChatbotState> {
  static const _streamUpdateInterval = Duration(milliseconds: 50);

  ChatbotBloc({required SendChatMessageUseCase sendMessage})
    : _sendMessage = sendMessage,
      super(ChatbotState.initial()) {
    on<ChatbotMessageSubmitted>(_onMessageSubmitted);
    on<ChatbotMessageEdited>(_onMessageEdited);
    on<ChatbotStreamStopped>(_onStreamStopped);
  }

  final SendChatMessageUseCase _sendMessage;
  void Function()? _activeStreamCanceller;
  bool _isStoppedByUser = false;

  void _onStreamStopped(
    ChatbotStreamStopped event,
    Emitter<ChatbotState> emit,
  ) {
    if (!state.isSending) return;
    _isStoppedByUser = true;
    _activeStreamCanceller?.call();
    _activeStreamCanceller = null;
  }

  Stream<ChatStreamEvent> _bufferChatDeltas(Stream<ChatStreamEvent> source) {
    late final StreamController<ChatStreamEvent> controller;
    StreamSubscription<ChatStreamEvent>? subscription;
    Timer? flushTimer;
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

    void cancelActiveStream() {
      if (sourceFinished) return;
      sourceFinished = true;
      stopTimer();
      flushDeltas();
      subscription?.cancel();
      if (!controller.isClosed) {
        controller.close();
      }
    }

    controller = StreamController<ChatStreamEvent>(
      onListen: () {
        _activeStreamCanceller = cancelActiveStream;
        flushTimer = Timer.periodic(
          _streamUpdateInterval,
          (_) => flushDeltas(),
        );
        subscription = source.listen(
          (event) {
            if (event case ChatDeltaEvent(:final text)) {
              deltaBuffer.write(text);
              return;
            }

            flushDeltas();
            controller.add(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            sourceFinished = true;
            stopTimer();
            flushDeltas();
            _activeStreamCanceller = null;
            controller.addError(error, stackTrace);
            controller.close();
          },
          onDone: () {
            sourceFinished = true;
            stopTimer();
            flushDeltas();
            _activeStreamCanceller = null;
            controller.close();
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        stopTimer();
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
  }) async {
    _activeStreamCanceller = null;
    _isStoppedByUser = false;

    final startTime = DateTime.now();
    final messageId =
        'msg_${startTime.millisecondsSinceEpoch}_${query.hashCode.abs()}';
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
    try {
      await emit.forEach<ChatStreamEvent>(
        _bufferChatDeltas(
          _sendMessage.executeStream(query: query, history: history),
        ),
        onData: (event) {
          final currentMessages = List<ChatMessage>.from(state.messages);
          if (currentMessages.isEmpty) return state;
          final lastIndex = currentMessages.length - 1;
          final last = currentMessages[lastIndex];
          if (last.role != ChatMessageRole.assistant) return state;

          switch (event) {
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
            case ChatMetadataEvent(:final recommendedItems, :final questions):
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
              );
              return state.copyWith(messages: currentMessages);
            case ChatDeltaEvent(:final text):
              final isFirstDelta = last.content.isEmpty && text.isNotEmpty;
              final updatedDuration = isFirstDelta
                  ? (last.responseDuration ??
                        (stopwatch.elapsed.inMilliseconds > 0
                            ? stopwatch.elapsed
                            : const Duration(seconds: 1)))
                  : last.responseDuration;
              currentMessages[lastIndex] = last.copyWith(
                content: last.content + text,
                responseDuration: updatedDuration,
                statusMessage: isFirstDelta
                    ? 'สรุปคำแนะนำ'
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
            ):
              stopwatch.stop();
              final effectiveQuestions = questions.isNotEmpty
                  ? questions
                  : last.questions;
              final effectiveRecommended = effectiveQuestions.isNotEmpty
                  ? const <RecommendedItem>[]
                  : (recommendedItems.isNotEmpty
                        ? recommendedItems
                        : last.recommendedItems);
              final effectiveContent = answer?.trim().isNotEmpty == true
                  ? answer!.trim()
                  : last.content;
              final effectiveActivities = activities.isNotEmpty
                  ? activities
                  : last.activities;
              final effectiveDuration =
                  last.responseDuration ??
                  (stopwatch.elapsed.inMilliseconds > 0
                      ? stopwatch.elapsed
                      : const Duration(seconds: 1));
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
                isStreaming: false,
                responseDuration: effectiveDuration,
                statusMessage: 'สรุปคำแนะนำ',
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
        final currentMessages = List<ChatMessage>.from(state.messages);
        const errorMessage = 'การตอบกลับไม่สมบูรณ์ กรุณาลองใหม่อีกครั้ง';
        if (currentMessages.isNotEmpty &&
            currentMessages.last.role == ChatMessageRole.assistant) {
          currentMessages[currentMessages.length - 1] = currentMessages.last
              .copyWith(
                content: errorMessage,
                isStreaming: false,
                responseDuration: stopwatch.elapsed,
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
            return selected == null ? q : q.copyWith(selectedOption: selected);
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
      emit: emit,
    );
  }

  @override
  Future<void> close() {
    _activeStreamCanceller?.call();
    _activeStreamCanceller = null;
    _sendMessage.close();
    return super.close();
  }
}
