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
  }) async {
    try {
      return await remoteDataSource.sendMessage(query: query, history: history);
    } on ChatbotRemoteException catch (error) {
      throw ChatbotException(error.message);
    }
  }

  @override
  Stream<ChatStreamEvent> sendMessageStream({
    required String query,
    required List<ChatMessage> history,
  }) async* {
    try {
      yield* remoteDataSource.sendMessageStream(query: query, history: history);
    } on ChatbotRemoteException catch (error) {
      throw ChatbotException(error.message);
    }
  }

  @override
  Future<void> submitFeedback({
    required String messageId,
    required String userQuery,
    required String aiResponse,
    required int rating,
    String? reasonCategory,
    String? feedbackComment,
    String? resolvedMode,
  }) async {
    await remoteDataSource.sendFeedback(
      messageId: messageId,
      userQuery: userQuery,
      aiResponse: aiResponse,
      rating: rating,
      reasonCategory: reasonCategory,
      feedbackComment: feedbackComment,
      resolvedMode: resolvedMode,
    );
  }

  @override
  void close() {
    remoteDataSource.close();
  }
}
