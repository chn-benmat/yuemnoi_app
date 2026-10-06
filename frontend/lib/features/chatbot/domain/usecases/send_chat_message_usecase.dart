import '../entities/chat_message.dart';
import '../repositories/chatbot_repository.dart';

class SendChatMessageUseCase {
  const SendChatMessageUseCase(this.repository);

  final ChatbotRepository repository;

  Future<ChatResponse> execute({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) {
    return repository.sendMessage(
      query: query,
      history: history,
      sessionId: sessionId,
      context: context,
      questionnaireAnswers: questionnaireAnswers,
      questionnaireSkipped: questionnaireSkipped,
      activeQuestionId: activeQuestionId,
    );
  }

  Stream<ChatStreamEvent> executeStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) {
    return repository.sendMessageStream(
      query: query,
      history: history,
      sessionId: sessionId,
      context: context,
      questionnaireAnswers: questionnaireAnswers,
      questionnaireSkipped: questionnaireSkipped,
      activeQuestionId: activeQuestionId,
    );
  }

  void close() {
    repository.close();
  }
}
