import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

class StreamMessagesUseCase {
  const StreamMessagesUseCase(this._repository);

  final ChatRepository _repository;

  Stream<List<ChatMessage>> call(String conversationId) {
    return _repository.streamMessages(conversationId);
  }
}
