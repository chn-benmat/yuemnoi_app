import '../entities/chat_message.dart';

class ChatbotException implements Exception {
  const ChatbotException(
    this.message, {
    this.errorCode,
    this.statusCode,
    this.retryAfterSeconds,
  });

  final String message;
  final String? errorCode;
  final int? statusCode;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

abstract interface class ChatbotRepository {
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  });

  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  });

  void close();
}
