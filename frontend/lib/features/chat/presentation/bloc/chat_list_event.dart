import 'package:equatable/equatable.dart';
import '../../domain/entities/chat_conversation.dart';

abstract class ChatListEvent extends Equatable {
  const ChatListEvent();

  @override
  List<Object?> get props => [];
}

class LoadChatListStarted extends ChatListEvent {
  const LoadChatListStarted();
}

class ChatListRefreshed extends ChatListEvent {
  const ChatListRefreshed();
}

class ChatConversationMarkedAsRead extends ChatListEvent {
  const ChatConversationMarkedAsRead(this.conversationId);
  final String conversationId;

  @override
  List<Object?> get props => [conversationId];
}

class ChatConversationsUpdated extends ChatListEvent {
  const ChatConversationsUpdated(this.conversations);
  final List<ChatConversation> conversations;

  @override
  List<Object?> get props => [conversations];
}

class ChatConversationDeleted extends ChatListEvent {
  const ChatConversationDeleted(this.conversationId);
  final String conversationId;

  @override
  List<Object?> get props => [conversationId];
}
