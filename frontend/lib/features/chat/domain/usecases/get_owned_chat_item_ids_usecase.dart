import '../repositories/chat_repository.dart';

class GetOwnedChatItemIdsUseCase {
  const GetOwnedChatItemIdsUseCase(this._repository);

  final ChatRepository _repository;

  Future<Set<int>> call(Set<int> itemIds) {
    return _repository.getOwnedItemIds(itemIds);
  }
}
