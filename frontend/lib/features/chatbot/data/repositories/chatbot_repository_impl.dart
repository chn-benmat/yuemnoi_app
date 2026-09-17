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
  }) {
    return remoteDataSource
        .sendMessageStream(query: query, history: history)
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
