import 'dart:typed_data';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({ChatRemoteDataSource? remoteDataSource})
      : _remoteDataSource = remoteDataSource ?? ChatRemoteDataSource();

  final ChatRemoteDataSource _remoteDataSource;

  @override
  Future<ChatConversation> getOrCreateConversation({
    int? itemId,
    required String ownerId,
  }) {
    return _remoteDataSource.getOrCreateConversation(
      itemId: itemId,
      ownerId: ownerId,
    );
  }

  @override
  Future<List<ChatConversation>> getConversations() {
    return _remoteDataSource.getConversations();
  }

  @override
  Future<String> getConversationContactPhone(String conversationId) {
    return _remoteDataSource.getConversationContactPhone(conversationId);
  }

  @override
  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    DateTime? before,
    int limit = 25,
  }) {
    return _remoteDataSource.fetchMessages(
      conversationId: conversationId,
      before: before,
      limit: limit,
    );
  }

  @override
  Stream<List<ChatMessage>> streamMessages(String conversationId) {
    return _remoteDataSource.streamMessages(conversationId);
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String message,
    String? imageUrl,
  }) {
    return _remoteDataSource.sendMessage(
      conversationId: conversationId,
      message: message,
      imageUrl: imageUrl,
    );
  }

  @override
  Future<void> markMessagesAsRead(String conversationId) {
    return _remoteDataSource.markMessagesAsRead(conversationId: conversationId);
  }

  @override
  Future<String> uploadChatImage({
    required String conversationId,
    required Uint8List imageBytes,
    required String fileName,
  }) {
    return _remoteDataSource.uploadChatImage(
      conversationId: conversationId,
      imageBytes: imageBytes,
      fileName: fileName,
    );
  }
}
