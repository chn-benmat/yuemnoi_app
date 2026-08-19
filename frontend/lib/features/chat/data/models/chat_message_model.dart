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

    final bool isMine;
    if (currentUserId.isNotEmpty && senderId.isNotEmpty && senderId != 'me') {
      isMine = (currentUserId == senderId);
    } else if (senderId == 'me') {
      isMine = true;
    } else {
      isMine = json['is_mine'] as bool? ?? false;
    }

    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      message: message,
      imageUrl: imageUrl?.isEmpty ?? true ? null : imageUrl,
      createdAt: createdAt,
      isMine: isMine,
      isRead: isRead,
    );
  }

  static Map<String, dynamic> toJson(ChatMessage message) {
    return {
      'id': message.id,
      'conversation_id': message.conversationId,
      'sender_id': message.senderId,
      'message': message.message,
      'image_url': message.imageUrl,
      'created_at': message.createdAt.toIso8601String(),
      'is_read': message.isRead,
      'is_mine': message.isMine,
    };
  }
}

