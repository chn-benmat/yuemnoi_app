import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/usecases/fetch_messages_usecase.dart';
import '../../domain/usecases/mark_messages_as_read_usecase.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import '../../domain/usecases/stream_messages_usecase.dart';
import '../../domain/usecases/upload_chat_image_usecase.dart';
import 'chat_detail_event.dart';
import 'chat_detail_state.dart';

/// In-memory fast cache for instant 0ms message loading like Messenger & LINE
class ChatMessagesCache {
  static final Map<String, List<ChatMessage>> _cache = {};

  static List<ChatMessage>? get(String conversationId) => _cache[conversationId];

  static void set(String conversationId, List<ChatMessage> messages) {
    if (messages.isNotEmpty) {
      _cache[conversationId] = List.unmodifiable(messages);
    }
  }

  static void clear() => _cache.clear();
}

class ChatDetailBloc extends Bloc<ChatDetailEvent, ChatDetailState> {
  ChatDetailBloc({
    required StreamMessagesUseCase streamMessages,
    required SendChatMessageUseCase sendMessage,
    FetchMessagesUseCase? fetchMessages,
    UploadChatImageUseCase? uploadChatImage,
    MarkMessagesAsReadUseCase? markMessagesAsRead,
    String? conversationId,
  })  : _streamMessages = streamMessages,
        _sendMessage = sendMessage,
        _fetchMessages = fetchMessages,
        _uploadChatImage = uploadChatImage,
        _markMessagesAsRead = markMessagesAsRead,
        super(ChatDetailState(
          messages: conversationId != null
              ? (ChatMessagesCache.get(conversationId) ?? const [])
              : const [],
          status: conversationId != null &&
                  (ChatMessagesCache.get(conversationId)?.isNotEmpty ?? false)
              ? ChatDetailStatus.success
              : ChatDetailStatus.initial,
        )) {
    on<ChatMessagesSubscriptionRequested>(_onSubscriptionRequested);
    on<ChatMessagesUpdated>(_onMessagesUpdated);
    on<ChatOlderMessagesRequested>(_onOlderMessagesRequested);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatImageUploadedAndSent>(_onImageUploadedAndSent);
  }

  final StreamMessagesUseCase _streamMessages;
  final SendChatMessageUseCase _sendMessage;
  final FetchMessagesUseCase? _fetchMessages;
  final UploadChatImageUseCase? _uploadChatImage;
  final MarkMessagesAsReadUseCase? _markMessagesAsRead;

  StreamSubscription<List<ChatMessage>>? _messagesSubscription;

  Future<void> _onSubscriptionRequested(
    ChatMessagesSubscriptionRequested event,
    Emitter<ChatDetailState> emit,
  ) async {
    // If cached messages exist and state is currently empty, load cache immediately
    final cached = ChatMessagesCache.get(event.conversationId);
    if (cached != null && cached.isNotEmpty && state.messages.isEmpty) {
      emit(state.copyWith(
        status: ChatDetailStatus.success,
        messages: cached,
      ));
    }

    await _messagesSubscription?.cancel();
    try {
      _markMessagesAsRead?.call(event.conversationId);

      _messagesSubscription = _streamMessages(event.conversationId).listen(
        (messages) => add(ChatMessagesUpdated(messages)),
        onError: (error) {
          if (!isClosed) {
            emit(state.copyWith(
              status: ChatDetailStatus.failure,
              errorMessage: error.toString(),
            ));
          }
        },
      );
    } catch (e) {
      emit(state.copyWith(
        status: ChatDetailStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onMessagesUpdated(
    ChatMessagesUpdated event,
    Emitter<ChatDetailState> emit,
  ) {
    if (event.messages.isNotEmpty) {
      ChatMessagesCache.set(
        event.messages.first.conversationId,
        event.messages,
      );
      final unreadIncoming = event.messages.any((m) => !m.isMine && !m.isRead);
      if (unreadIncoming) {
        _markMessagesAsRead?.call(event.messages.first.conversationId);
      }
    }

    emit(state.copyWith(
      status: ChatDetailStatus.success,
      messages: event.messages,
    ));
  }

  Future<void> _onOlderMessagesRequested(
    ChatOlderMessagesRequested event,
    Emitter<ChatDetailState> emit,
  ) async {
    if (_fetchMessages == null || state.isFetchingOlder || state.hasReachedMax) {
      return;
    }

    if (state.messages.isEmpty) return;

    final oldestMessageDate = state.messages.first.createdAt;
    emit(state.copyWith(isFetchingOlder: true));

    try {
      final olderMessages = await _fetchMessages(
        conversationId: event.conversationId,
        before: oldestMessageDate,
        limit: 25,
      );

      if (olderMessages.isEmpty) {
        emit(state.copyWith(
          isFetchingOlder: false,
          hasReachedMax: true,
        ));
        return;
      }

      // Prepend older messages before existing messages
      final existingIds = state.messages.map((m) => m.id).toSet();
      final newOlder = olderMessages.where((m) => !existingIds.contains(m.id)).toList();

      emit(state.copyWith(
        isFetchingOlder: false,
        hasReachedMax: olderMessages.length < 25,
        messages: [...newOlder, ...state.messages],
      ));
    } catch (_) {
      emit(state.copyWith(isFetchingOlder: false));
    }
  }

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatDetailState> emit,
  ) async {
    final trimmed = event.message.trim();
    if (trimmed.isEmpty) return;

    try {
      await _sendMessage(
        conversationId: event.conversationId,
        message: trimmed,
      );
    } catch (e) {
      emit(state.copyWith(
        status: ChatDetailStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onImageUploadedAndSent(
    ChatImageUploadedAndSent event,
    Emitter<ChatDetailState> emit,
  ) async {
    if (_uploadChatImage == null) return;
    emit(state.copyWith(isUploadingImage: true));

    try {
      final imageUrl = await _uploadChatImage(
        conversationId: event.conversationId,
        imageBytes: event.imageBytes,
        fileName: event.fileName,
      );

      if (imageUrl.isNotEmpty) {
        await _sendMessage(
          conversationId: event.conversationId,
          message: '📷 ส่งรูปภาพ',
          imageUrl: imageUrl,
        );
      }
      emit(state.copyWith(isUploadingImage: false));
    } catch (e) {
      emit(state.copyWith(
        isUploadingImage: false,
        status: ChatDetailStatus.failure,
        errorMessage: 'อัปโหลดรูปภาพไม่สำเร็จ: ${e.toString()}',
      ));
    }
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
