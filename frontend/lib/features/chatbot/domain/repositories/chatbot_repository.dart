import '../entities/chat_message.dart';

class ChatbotException implements Exception {
  const ChatbotException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ChatbotRepository {
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
  });

  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
  });

  Future<void> submitFeedback({
    required String messageId,
    required String userQuery,
    required String aiResponse,
    required int rating,
    String? reasonCategory,
    String? feedbackComment,
    String? resolvedMode,
  });

  void close();
}
