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
    on<ChatbotFeedbackSubmitted>(_onFeedbackSubmitted);
  }

  final SendChatMessageUseCase _sendMessage;

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

    controller = StreamController<ChatStreamEvent>(
      onListen: () {
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
            controller.addError(error, stackTrace);
            controller.close();
          },
          onDone: () {
            sourceFinished = true;
            stopTimer();
            flushDeltas();
            controller.close();
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        stopTimer();
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
    final messageId =
        'msg_${DateTime.now().millisecondsSinceEpoch}_${query.hashCode.abs()}';
    final placeholder = ChatMessage(
      id: messageId,
      role: ChatMessageRole.assistant,
      content: '',
      userQuery: query,
      isStreaming: true,
    );

    emit(
      state.copyWith(
        messages: [...messagesWithUser, placeholder],
        isSending: true,
        clearError: true,
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
            case ChatStatusEvent():
              return state;
            case ChatMetadataEvent(:final recommendedItems, :final questions):
              final effectiveQuestions =
                  questions.isNotEmpty ? questions : last.questions;
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
              currentMessages[lastIndex] = last.copyWith(
                content: last.content + text,
              );
              return state.copyWith(messages: currentMessages);
            case ChatDoneEvent(
              :final suggestedReplies,
              :final recommendedItems,
              :final questions,
            ):
              stopwatch.stop();
              final effectiveQuestions =
                  questions.isNotEmpty ? questions : last.questions;
              final effectiveRecommended = effectiveQuestions.isNotEmpty
                  ? const <RecommendedItem>[]
                  : (recommendedItems.isNotEmpty
                      ? recommendedItems
                      : last.recommendedItems);
              var effectiveContent = last.content;
              if (effectiveContent.trim().isEmpty) {
                if (effectiveQuestions.isNotEmpty) {
                  effectiveContent =
                      'เพื่อช่วยแนะนำอุปกรณ์ที่เหมาะสมและคุ้มค่าที่สุด รบกวนเลือกข้อมูลการใช้งานด้านล่างนี้ได้เลยนะคะ 😊';
                } else if (effectiveRecommended.isNotEmpty) {
                  effectiveContent = 'นี่คืออุปกรณ์ที่เราแนะนำสำหรับคุณค่ะ:';
                } else {
                  effectiveContent =
                      'ขออภัยด้วยนะคะ ขณะนี้ระบบไม่สามารถประมวลผลคำตอบได้ กรุณาลองใหม่อีกครั้งค่ะ';
                }
              }
              currentMessages[lastIndex] = last.copyWith(
                content: effectiveContent,
                suggestedReplies: suggestedReplies.isNotEmpty
                    ? suggestedReplies
                    : last.suggestedReplies,
                recommendedItems: effectiveRecommended,
                questions: effectiveQuestions,
                responseDuration: stopwatch.elapsed,
                isStreaming: false,
              );
              return state.copyWith(
                messages: currentMessages,
                isSending: false,
                clearError: true,
              );
          }
        },
        onError: (error, _) {
          stopwatch.stop();
          final currentMessages = List<ChatMessage>.from(state.messages);
          if (currentMessages.isNotEmpty &&
              currentMessages.last.role == ChatMessageRole.assistant &&
              currentMessages.last.content.isEmpty &&
              currentMessages.last.recommendedItems.isEmpty &&
              currentMessages.last.questions.isEmpty) {
            currentMessages.removeLast();
          } else if (currentMessages.isNotEmpty &&
              currentMessages.last.role == ChatMessageRole.assistant) {
            currentMessages[currentMessages.length - 1] = currentMessages.last
                .copyWith(isStreaming: false);
          }
          final errorMessage = error is ChatbotException
              ? error.message
              : 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
          return state.copyWith(
            messages: currentMessages,
            isSending: false,
            errorMessage: errorMessage,
          );
        },
      );

      if (state.isSending) {
        stopwatch.stop();
        final currentMessages = List<ChatMessage>.from(state.messages);
        if (currentMessages.isNotEmpty &&
            currentMessages.last.role == ChatMessageRole.assistant) {
          final last = currentMessages.last;
          final effectiveRecommended = last.questions.isNotEmpty
              ? const <RecommendedItem>[]
              : last.recommendedItems;
          var effectiveContent = last.content;
          if (effectiveContent.trim().isEmpty) {
            if (last.questions.isNotEmpty) {
              effectiveContent =
                  'เพื่อช่วยแนะนำอุปกรณ์ที่เหมาะสมและคุ้มค่าที่สุด รบกวนเลือกข้อมูลการใช้งานด้านล่างนี้ได้เลยนะคะ 😊';
            } else if (effectiveRecommended.isNotEmpty) {
              effectiveContent = 'นี่คืออุปกรณ์ที่เราแนะนำสำหรับคุณค่ะ:';
            } else {
              effectiveContent =
                  'ขออภัยด้วยนะคะ ขณะนี้ระบบไม่สามารถประมวลผลคำตอบได้ กรุณาลองใหม่อีกครั้งค่ะ';
            }
          }
          currentMessages[currentMessages.length - 1] = last.copyWith(
            content: effectiveContent,
            recommendedItems: effectiveRecommended,
            isStreaming: false,
            responseDuration:
                last.responseDuration ?? stopwatch.elapsed,
          );
        }
        emit(state.copyWith(messages: currentMessages, isSending: false));
      }
    } catch (_) {
      stopwatch.stop();
      emit(
        state.copyWith(
          isSending: false,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
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
      final parts = query.split(',').map((s) => s.trim()).toList();
      final updatedQuestions = <ClarificationQuestion>[];
      for (var i = 0; i < lastAssistant.questions.length; i++) {
        final q = lastAssistant.questions[i];
        if (q.selectedOption != null) {
          updatedQuestions.add(q);
        } else if (i < parts.length && parts[i].isNotEmpty) {
          updatedQuestions.add(q.copyWith(selectedOption: parts[i]));
        } else {
          updatedQuestions.add(q.copyWith(selectedOption: query));
        }
      }
      history[history.length - 1] = lastAssistant.copyWith(
        questions: updatedQuestions,
      );
    }

    final messagesWithQuestion = [
      ...history,
      ChatMessage(role: ChatMessageRole.user, content: query),
    ];

    await _handleMessageStream(
      query: query,
      history: history,
      messagesWithUser: messagesWithQuestion,
      emit: emit,
    );
  }

  Future<void> _onFeedbackSubmitted(
    ChatbotFeedbackSubmitted event,
    Emitter<ChatbotState> emit,
  ) async {
    final idx = event.messageIndex;
    if (idx < 0 || idx >= state.messages.length) return;
    final msg = state.messages[idx];
    if (msg.role != ChatMessageRole.assistant) return;

    final newIsLiked = msg.isLiked == event.isLiked ? null : event.isLiked;
    final updated = msg.copyWith(
      isLiked: newIsLiked,
      feedbackReason: event.reasonCategory,
      feedbackComment: event.feedbackComment,
    );

    final currentMessages = List<ChatMessage>.from(state.messages);
    currentMessages[idx] = updated;
    emit(state.copyWith(messages: currentMessages));

    if (newIsLiked != null) {
      final userQuery =
          updated.userQuery ??
          (idx > 0 && state.messages[idx - 1].role == ChatMessageRole.user
              ? state.messages[idx - 1].content
              : '');
      _sendMessage
          .submitFeedback(
            messageId: updated.id.isNotEmpty
                ? updated.id
                : 'msg_${idx}_${DateTime.now().millisecondsSinceEpoch}',
            userQuery: userQuery,
            aiResponse: updated.content,
            rating: newIsLiked ? 1 : -1,
            reasonCategory: event.reasonCategory,
            feedbackComment: event.feedbackComment,
          )
          .ignore();
    }
  }

  @override
  Future<void> close() {
    _sendMessage.close();
    return super.close();
  }
}
