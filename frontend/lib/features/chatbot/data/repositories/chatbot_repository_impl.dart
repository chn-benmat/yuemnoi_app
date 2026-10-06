import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chatbot_repository.dart';
import '../datasources/chatbot_remote_data_source.dart';

class ChatbotRepositoryImpl implements ChatbotRepository {
  const ChatbotRepositoryImpl(this.remoteDataSource);

  final ChatbotRemoteDataSource remoteDataSource;

  @override
  Future<ChatResponse> sendMessage({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) async {
    try {
      return await remoteDataSource.sendMessage(
        query: query,
        history: history,
        sessionId: sessionId,
        context: context,
        questionnaireAnswers: questionnaireAnswers,
        questionnaireSkipped: questionnaireSkipped,
        activeQuestionId: activeQuestionId,
      );
    } on ChatbotRemoteException catch (error) {
      throw ChatbotException(error.message);
    }
  }

  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
    String? sessionId,
    ChatSessionContext? context,
    List<QuestionnaireAnswer> questionnaireAnswers = const [],
    bool questionnaireSkipped = false,
    String? activeQuestionId,
  }) {
    return remoteDataSource
        .sendMessageStream(
          query: query,
          history: history,
          sessionId: sessionId,
          context: context,
          questionnaireAnswers: questionnaireAnswers,
          questionnaireSkipped: questionnaireSkipped,
          activeQuestionId: activeQuestionId,
        )
        .handleError((error) {
          if (error is ChatbotRemoteException) {
            throw ChatbotException(error.message);
          }
          throw error;
        });
  }

  @override
  void close() {
    remoteDataSource.close();
  }
}
