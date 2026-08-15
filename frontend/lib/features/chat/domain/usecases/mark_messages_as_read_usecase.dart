import '../repositories/chat_repository.dart';

class MarkMessagesAsReadUseCase {
  const MarkMessagesAsReadUseCase(this._repository);

  final ChatRepository _repository;

  Future<void> call(String conversationId) {
    return _repository.markMessagesAsRead(conversationId);
  }
}
