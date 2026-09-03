import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chatbot_repository.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import 'chatbot_event.dart';
import 'chatbot_state.dart';

class ChatbotBloc extends Bloc<ChatbotEvent, ChatbotState> {
  ChatbotBloc({required SendChatMessageUseCase sendMessage})
    : _sendMessage = sendMessage,
      super(ChatbotState.initial()) {
    on<ChatbotMessageSubmitted>(_onMessageSubmitted);
    on<ChatbotMessageEdited>(_onMessageEdited);
  }

  final SendChatMessageUseCase _sendMessage;

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
    emit(
      state.copyWith(
        messages: messagesWithEditedQuestion,
        isSending: true,
        clearError: true,
      ),
    );

    try {
      final response = await _sendMessage.execute(
        query: content,
        history: history,
      );
      emit(
        state.copyWith(
          messages: [
            ...messagesWithEditedQuestion,
            ChatMessage(
              role: ChatMessageRole.assistant,
              content: response.answer,
              recommendedItems: response.recommendedItems,
            ),
          ],
          isSending: false,
          clearError: true,
        ),
      );
    } on ChatbotException catch (error) {
      emit(state.copyWith(isSending: false, errorMessage: error.message));
    } catch (_) {
      emit(
        state.copyWith(
          isSending: false,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
        ),
      );
    }
  }

  Future<void> _onMessageSubmitted(
    ChatbotMessageSubmitted event,
    Emitter<ChatbotState> emit,
  ) async {
    final query = event.query.trim();
    if (query.isEmpty || state.isSending) return;

    final history = state.messages;
    final messagesWithQuestion = [
      ...history,
      ChatMessage(role: ChatMessageRole.user, content: query),
    ];
    emit(
      state.copyWith(
        messages: messagesWithQuestion,
        isSending: true,
        clearError: true,
      ),
    );

    try {
      final response = await _sendMessage.execute(
        query: query,
        history: history,
      );
      emit(
        state.copyWith(
          messages: [
            ...messagesWithQuestion,
            ChatMessage(
              role: ChatMessageRole.assistant,
              content: response.answer,
              recommendedItems: response.recommendedItems,
            ),
          ],
          isSending: false,
          clearError: true,
        ),
      );
    } on ChatbotException catch (error) {
      emit(state.copyWith(isSending: false, errorMessage: error.message));
    } catch (_) {
      emit(
        state.copyWith(
          isSending: false,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _sendMessage.close();
    return super.close();
  }
}
