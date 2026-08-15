import 'package:equatable/equatable.dart';

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.message,
    required this.createdAt,
    required this.isMine,
    this.imageUrl,
    this.isRead = true,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String message;
  final DateTime createdAt;
  final bool isMine;
  final String? imageUrl;
  final bool isRead;

  @override
  List<Object?> get props => [
    id,
    conversationId,
    senderId,
    message,
    createdAt,
    isMine,
    imageUrl,
    isRead,
  ];
}
