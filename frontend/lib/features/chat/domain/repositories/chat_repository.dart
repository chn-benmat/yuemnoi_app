import 'dart:typed_data';

import '../entities/chat_conversation.dart';
import '../entities/chat_message.dart';

abstract class ChatRepository {
  Future<ChatConversation> getOrCreateConversation({
    int? itemId,
    required String ownerId,
  });

  Future<List<ChatConversation>> getConversations();

  Future<String> getConversationContactPhone(String conversationId);

  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    DateTime? before,
    int limit = 25,
  });

  Stream<List<ChatMessage>> streamMessages(String conversationId);

  Future<void> sendMessage({
    required String conversationId,
    required String message,
    String? imageUrl,
  });

  Future<void> markMessagesAsRead(String conversationId);

  Future<String> uploadChatImage({
    required String conversationId,
    required Uint8List imageBytes,
    required String fileName,
  });
}
