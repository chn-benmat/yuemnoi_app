import '../entities/chat_message.dart';
import '../repositories/chatbot_repository.dart';

class SendChatMessageUseCase {
  const SendChatMessageUseCase(this.repository);

  final ChatbotRepository repository;

  Future<ChatResponse> execute({
    required String query,
    required List<ChatMessage> history,
  }) {
    return repository.sendMessage(query: query, history: history);
  }

  Stream<ChatStreamEvent> executeStream({
    required String query,
    required List<ChatMessage> history,
  }) {
    return repository.sendMessageStream(query: query, history: history);
  }

  Future<void> submitFeedback({
    required String messageId,
    required String userQuery,
    required String aiResponse,
    required int rating,
    String? reasonCategory,
    String? feedbackComment,
    String? resolvedMode,
  }) {
    return repository.submitFeedback(
      messageId: messageId,
      userQuery: userQuery,
      aiResponse: aiResponse,
      rating: rating,
      reasonCategory: reasonCategory,
      feedbackComment: feedbackComment,
      resolvedMode: resolvedMode,
    );
  }

  void close() {
    repository.close();
  }
}
