import '../repositories/chat_repository.dart';

class GetConversationContactPhoneUseCase {
  const GetConversationContactPhoneUseCase(this._repository);

  final ChatRepository _repository;

  Future<String> call(String conversationId) {
    return _repository.getConversationContactPhone(conversationId);
  }
}
