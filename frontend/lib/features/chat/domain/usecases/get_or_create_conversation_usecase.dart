import '../entities/chat_conversation.dart';
import '../repositories/chat_repository.dart';

class GetOrCreateConversationUseCase {
  const GetOrCreateConversationUseCase(this._repository);

  final ChatRepository _repository;

  Future<ChatConversation> call({
    required int itemId,
    required String ownerId,
  }) {
    return _repository.getOrCreateConversation(
      itemId: itemId,
      ownerId: ownerId,
    );
  }
}
