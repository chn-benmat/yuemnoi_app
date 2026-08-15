import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/get_conversations_usecase.dart';
import 'chat_list_event.dart';
import 'chat_list_state.dart';

class ChatListBloc extends Bloc<ChatListEvent, ChatListState> {
  ChatListBloc({required GetConversationsUseCase getConversations})
      : _getConversations = getConversations,
        super(const ChatListState()) {
    on<LoadChatListStarted>(_onLoadChatListStarted);
    on<ChatListRefreshed>(_onChatListRefreshed);
    on<ChatConversationMarkedAsRead>(_onConversationMarkedAsRead);
  }

  final GetConversationsUseCase _getConversations;

  Future<void> _onLoadChatListStarted(
    LoadChatListStarted event,
    Emitter<ChatListState> emit,
  ) async {
    emit(state.copyWith(status: ChatListStatus.loading));
    try {
      final conversations = await _getConversations();
      emit(state.copyWith(
        status: ChatListStatus.success,
        conversations: conversations,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ChatListStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onChatListRefreshed(
    ChatListRefreshed event,
    Emitter<ChatListState> emit,
  ) async {
    try {
      final conversations = await _getConversations();
      emit(state.copyWith(
        status: ChatListStatus.success,
        conversations: conversations,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ChatListStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onConversationMarkedAsRead(
    ChatConversationMarkedAsRead event,
    Emitter<ChatListState> emit,
  ) {
    final updatedList = state.conversations.map((c) {
      if (c.id == event.conversationId) {
        return c.copyWith(hasUnreadMessage: false);
      }
      return c;
    }).toList();

    emit(state.copyWith(conversations: updatedList));
  }
}
