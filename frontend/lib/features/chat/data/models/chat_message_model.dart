import '../../domain/entities/chat_message.dart';

abstract final class ChatMessageModel {
  static ChatMessage fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    final id = json['id'].toString();
    final conversationId = json['conversation_id']?.toString() ?? '';
    final senderId = json['sender_id']?.toString() ?? '';
    final message = json['message']?.toString() ?? '';
    final imageUrl = json['image_url']?.toString();
    final createdAtStr = json['created_at']?.toString();
    final createdAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr)?.toLocal() ?? DateTime.now()
        : DateTime.now();
    final isRead = json['is_read'] as bool? ?? false;

    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      message: message,
      imageUrl: imageUrl?.isEmpty ?? true ? null : imageUrl,
      createdAt: createdAt,
      isMine: currentUserId == senderId,
      isRead: isRead,
    );
  }
}
