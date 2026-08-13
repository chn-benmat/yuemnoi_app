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

  void close() {
    repository.close();
  }
}
