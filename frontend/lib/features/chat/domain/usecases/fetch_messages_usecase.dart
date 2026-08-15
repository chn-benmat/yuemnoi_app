import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

class FetchMessagesUseCase {
  const FetchMessagesUseCase(this._repository);

  final ChatRepository _repository;

  Future<List<ChatMessage>> call({
    required String conversationId,
    DateTime? before,
    int limit = 25,
  }) {
    return _repository.fetchMessages(
      conversationId: conversationId,
      before: before,
      limit: limit,
    );
  }
}
