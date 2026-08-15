import 'dart:typed_data';

import '../repositories/chat_repository.dart';

class UploadChatImageUseCase {
  const UploadChatImageUseCase(this._repository);

  final ChatRepository _repository;

  Future<String> call({
    required String conversationId,
    required Uint8List imageBytes,
    required String fileName,
  }) {
    return _repository.uploadChatImage(
      conversationId: conversationId,
      imageBytes: imageBytes,
      fileName: fileName,
    );
  }
}
