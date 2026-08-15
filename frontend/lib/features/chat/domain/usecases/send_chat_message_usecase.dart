import '../repositories/chat_repository.dart';

class SendChatMessageUseCase {
  const SendChatMessageUseCase(this._repository);

  final ChatRepository _repository;

  Future<void> call({
    required String conversationId,
    required String message,
    String? imageUrl,
  }) {
    return _repository.sendMessage(
      conversationId: conversationId,
      message: message,
      imageUrl: imageUrl,
    );
  }
}
