import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import '../../domain/entities/chat_message.dart';

abstract class ChatDetailEvent extends Equatable {
  const ChatDetailEvent();

  @override
  List<Object?> get props => [];
}

class ChatMessagesSubscriptionRequested extends ChatDetailEvent {
  const ChatMessagesSubscriptionRequested(this.conversationId);

  final String conversationId;

  @override
  List<Object?> get props => [conversationId];
}

class ChatMessagesUpdated extends ChatDetailEvent {
  const ChatMessagesUpdated(this.messages);

  final List<ChatMessage> messages;

  @override
  List<Object?> get props => [messages];
}

class ChatOlderMessagesRequested extends ChatDetailEvent {
  const ChatOlderMessagesRequested(this.conversationId);

  final String conversationId;

  @override
  List<Object?> get props => [conversationId];
}

class ChatMessageSent extends ChatDetailEvent {
  const ChatMessageSent({
    required this.conversationId,
    required this.message,
    this.imageUrl,
  });

  final String conversationId;
  final String message;
  final String? imageUrl;

  @override
  List<Object?> get props => [conversationId, message, imageUrl];
}

class ChatImageUploadedAndSent extends ChatDetailEvent {
  const ChatImageUploadedAndSent({
    required this.conversationId,
    required this.imageBytes,
    required this.fileName,
    this.caption,
  });

  final String conversationId;
  final Uint8List imageBytes;
  final String fileName;
  final String? caption;

  @override
  List<Object?> get props => [conversationId, imageBytes, fileName, caption];
}
