import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/chat_pin_service.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/usecases/get_conversations_usecase.dart';
import 'chat_list_event.dart';
import 'chat_list_state.dart';

class ChatListBloc extends Bloc<ChatListEvent, ChatListState> {
  ChatListBloc({
    required GetConversationsUseCase getConversations,
    ChatRemoteDataSource? chatRemoteDataSource,
  }) : _getConversations = getConversations,
       _chatRemoteDataSource = chatRemoteDataSource ?? ChatRemoteDataSource(),
       super(const ChatListState()) {
    on<LoadChatListStarted>(_onLoadChatListStarted);
    on<ChatListRefreshed>(_onChatListRefreshed);
    on<ChatConversationsUpdated>(_onConversationsUpdated);
    on<ChatConversationMarkedAsRead>(_onConversationMarkedAsRead);
    on<ChatConversationDeleted>(_onConversationDeleted);
  }

  final GetConversationsUseCase _getConversations;
  final ChatRemoteDataSource _chatRemoteDataSource;
  StreamSubscription<List<ChatConversation>>? _conversationsSubscription;

  Future<void> _onLoadChatListStarted(
    LoadChatListStarted event,
    Emitter<ChatListState> emit,
  ) async {
    emit(state.copyWith(status: ChatListStatus.loading));
    try {
      final conversations = await _getConversations();
      emit(
        state.copyWith(
          status: ChatListStatus.success,
          conversations: conversations,
        ),
      );

      // ฟังการเปลี่ยนแปลงของรายการแชทแบบ Realtime (ข้อความล่าสุด, เวลา, ลำดับห้องแชท)
      _conversationsSubscription?.cancel();
      _conversationsSubscription = _chatRemoteDataSource
          .streamConversations()
          .listen((updatedList) {
            if (!isClosed) {
              add(ChatConversationsUpdated(updatedList));
            }
          });
    } catch (e) {
      emit(
        state.copyWith(
          status: ChatListStatus.failure,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onChatListRefreshed(
    ChatListRefreshed event,
    Emitter<ChatListState> emit,
  ) async {
    try {
      final conversations = await _getConversations();
      emit(
        state.copyWith(
          status: ChatListStatus.success,
          conversations: conversations,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: ChatListStatus.failure,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void _onConversationsUpdated(
    ChatConversationsUpdated event,
    Emitter<ChatListState> emit,
  ) {
    emit(
      state.copyWith(
        status: ChatListStatus.success,
        conversations: event.conversations,
      ),
    );
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

  Future<void> _onConversationDeleted(
    ChatConversationDeleted event,
    Emitter<ChatListState> emit,
  ) async {
    await ChatPinService.instance.unpin(event.conversationId);
    final updatedList = state.conversations
        .where((c) => c.id != event.conversationId)
        .toList();
    emit(state.copyWith(conversations: updatedList));

    try {
      await _chatRemoteDataSource.deleteConversation(
        conversationId: event.conversationId,
      );
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _conversationsSubscription?.cancel();
    return super.close();
  }
}
