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

class ChatImageData extends Equatable {
  const ChatImageData({
    required this.imageBytes,
    required this.fileName,
  });

  final Uint8List imageBytes;
  final String fileName;

  @override
  List<Object?> get props => [imageBytes, fileName];
}

class ChatMultipleImagesUploadedAndSent extends ChatDetailEvent {
  const ChatMultipleImagesUploadedAndSent({
    required this.conversationId,
    required this.images,
    this.caption,
  });

  final String conversationId;
  final List<ChatImageData> images;
  final String? caption;

  @override
  List<Object?> get props => [conversationId, images, caption];
}

class ChatMessageDeleted extends ChatDetailEvent {
  const ChatMessageDeleted({
    required this.conversationId,
    required this.messageId,
    this.imageUrl,
  });

  final String conversationId;
  final String messageId;
  final String? imageUrl;

  @override
  List<Object?> get props => [conversationId, messageId, imageUrl];
}

class ChatMessageEdited extends ChatDetailEvent {
  const ChatMessageEdited({
    required this.conversationId,
    required this.messageId,
    required this.newMessage,
  });

  final String conversationId;
  final String messageId;
  final String newMessage;

  @override
  List<Object?> get props => [conversationId, messageId, newMessage];
}

class ChatTypingStatusUpdated extends ChatDetailEvent {
  const ChatTypingStatusUpdated(this.isTyping);

  final bool isTyping;

  @override
  List<Object?> get props => [isTyping];
}

class ChatDirectMessageReceived extends ChatDetailEvent {
  const ChatDirectMessageReceived(this.message);

  final ChatMessage message;

  @override
  List<Object?> get props => [message];
}

class ChatReadReceiptsUpdated extends ChatDetailEvent {
  const ChatReadReceiptsUpdated(this.conversationId);

  final String conversationId;

  @override
  List<Object?> get props => [conversationId];
}

class ChatRetryMessageSent extends ChatDetailEvent {
  const ChatRetryMessageSent({
    required this.conversationId,
    required this.tempMessageId,
  });

  final String conversationId;
  final String tempMessageId;

  @override
  List<Object?> get props => [conversationId, tempMessageId];
}

