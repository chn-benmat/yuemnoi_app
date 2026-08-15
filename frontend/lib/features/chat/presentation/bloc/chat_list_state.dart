import 'package:equatable/equatable.dart';

import '../../domain/entities/chat_conversation.dart';

enum ChatListStatus { initial, loading, success, failure }

class ChatListState extends Equatable {
  const ChatListState({
    this.status = ChatListStatus.initial,
    this.conversations = const [],
    this.errorMessage,
  });

  final ChatListStatus status;
  final List<ChatConversation> conversations;
  final String? errorMessage;

  ChatListState copyWith({
    ChatListStatus? status,
    List<ChatConversation>? conversations,
    String? errorMessage,
  }) {
    return ChatListState(
      status: status ?? this.status,
      conversations: conversations ?? this.conversations,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, conversations, errorMessage];
}
