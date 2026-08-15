import 'package:equatable/equatable.dart';

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
