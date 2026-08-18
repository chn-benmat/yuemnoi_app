import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/models/chat_message_model.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/usecases/fetch_messages_usecase.dart';
import '../../domain/usecases/mark_messages_as_read_usecase.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import '../../domain/usecases/stream_messages_usecase.dart';
import '../../domain/usecases/upload_chat_image_usecase.dart';
import '../../../../core/network/supabase_client.dart';
import 'chat_detail_event.dart';
import 'chat_detail_state.dart';

/// In-memory & Persistent Disk cache for instant 0ms message loading like Messenger & LINE
class ChatMessagesCache {
  static final Map<String, List<ChatMessage>> _cache = {};

  static List<ChatMessage>? get(String conversationId) => _cache[conversationId];

  static void set(String conversationId, List<ChatMessage> messages) {
    if (messages.isNotEmpty) {
      _cache[conversationId] = List.unmodifiable(messages);
      _persistToDisk(conversationId, messages);
    }
  }

  static Future<void> _persistToDisk(String conversationId, List<ChatMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = messages.length > 50 ? messages.sublist(messages.length - 50) : messages;
      final jsonList = recent.map((m) => ChatMessageModel.toJson(m)).toList();
      await prefs.setString('chat_cache_$conversationId', jsonEncode(jsonList));
    } catch (_) {}
  }

  static Future<List<ChatMessage>?> loadFromDisk(
    String conversationId, {
    required String currentUserId,
  }) async {
    if (_cache.containsKey(conversationId) && _cache[conversationId]!.isNotEmpty) {
      return _cache[conversationId];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_cache_$conversationId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        final list = decoded
            .map((item) => ChatMessageModel.fromJson(
                  item as Map<String, dynamic>,
                  currentUserId: currentUserId,
                ))
            .toList();
        if (list.isNotEmpty) {
          _cache[conversationId] = List.unmodifiable(list);
          return list;
        }
      }
    } catch (_) {}
    return null;
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
    on<ChatMultipleImagesUploadedAndSent>(_onMultipleImagesUploadedAndSent);
    on<ChatMessageDeleted>(_onMessageDeleted);
    on<ChatMessageEdited>(_onMessageEdited);
    on<ChatTypingStatusUpdated>(_onTypingStatusUpdated);
    on<ChatDirectMessageReceived>(_onDirectMessageReceived);
    on<ChatReadReceiptsUpdated>(_onReadReceiptsUpdated);
    on<ChatRetryMessageSent>(_onRetryMessageSent);
  }

  final StreamMessagesUseCase _streamMessages;
  final SendChatMessageUseCase _sendMessage;
  final FetchMessagesUseCase? _fetchMessages;
  final UploadChatImageUseCase? _uploadChatImage;
  final MarkMessagesAsReadUseCase? _markMessagesAsRead;

  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  RealtimeChannel? _roomBroadcastChannel;

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

      // ⚡ Direct Realtime Room Broadcast (WebSocket Direct Delivery & Typing & Read)
      if (SupabaseConfig.isInitialized) {
        try {
          final client = SupabaseConfig.client;
          final currentUserId = client.auth.currentUser?.id ?? '';
          _roomBroadcastChannel?.unsubscribe();
          _roomBroadcastChannel = client.channel('chat_room:${event.conversationId}');

          _roomBroadcastChannel?.onBroadcast(event: 'new_message', callback: (payload) {
            try {
              final raw = payload['payload'];
              final Map<String, dynamic> msgMap = raw is Map<String, dynamic> ? raw : payload;
              if (msgMap.isNotEmpty) {
                final incoming = ChatMessageModel.fromJson(msgMap, currentUserId: currentUserId);
                if (!incoming.isMine) {
                  add(ChatDirectMessageReceived(incoming));
                }
              }
            } catch (_) {}
          });

          _roomBroadcastChannel?.onBroadcast(event: 'typing', callback: (payload) {
            try {
              final isTyping = payload['is_typing'] as bool? ?? false;
              final senderUid = payload['user_id'] as String?;
              if (senderUid != currentUserId) {
                add(ChatTypingStatusUpdated(isTyping));
              }
            } catch (_) {}
          });

          _roomBroadcastChannel?.onBroadcast(event: 'messages_read', callback: (payload) {
            try {
              final readerId = payload['reader_id'] as String?;
              if (readerId != currentUserId) {
                add(ChatReadReceiptsUpdated(event.conversationId));
              }
            } catch (_) {}
          });

          _roomBroadcastChannel?.subscribe();
        } catch (_) {}
      }
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

    // ข้อความของฉันที่ Server บันทึกและยืนยันแล้ว
    final serverMineTexts = event.messages
        .where((m) => m.isMine)
        .map((m) => '${m.message.trim()}_${m.imageUrl ?? ''}')
        .toSet();

    // รักษาเฉพาะข้อความ Optimistic ชั่วคราวที่เป็นของฉัน (isMine) และยังไม่ได้รับการบันทึกจาก Server
    // ข้อความจากฝั่งอื่น (isMine == false) ที่เคยรับผ่าน temporary broadcast จะถูกแทนที่ด้วยข้อมูลจริงจาก Server ทันที
    final pendingOptimistic = state.messages
        .where((m) =>
            m.isMine &&
            m.id.startsWith('temp_') &&
            !serverMineTexts.contains('${m.message.trim()}_${m.imageUrl ?? ''}'))
        .toList();

    // รวมและตัดข้อความซ้ำซ้อนตาม ID
    final seenIds = <String>{};
    final mergedMessages = <ChatMessage>[];

    for (final m in event.messages) {
      if (seenIds.add(m.id)) {
        mergedMessages.add(m);
      }
    }
    for (final m in pendingOptimistic) {
      if (seenIds.add(m.id)) {
        mergedMessages.add(m);
      }
    }

    emit(state.copyWith(
      status: ChatDetailStatus.success,
      messages: mergedMessages,
    ));
  }

  void _onDirectMessageReceived(
    ChatDirectMessageReceived event,
    Emitter<ChatDetailState> emit,
  ) {
    if (event.message.isMine) return;

    final isAlreadyPresent = state.messages.any((m) =>
        m.id == event.message.id ||
        (!m.id.startsWith('temp_') &&
            m.senderId == event.message.senderId &&
            m.message.trim() == event.message.message.trim() &&
            m.imageUrl == event.message.imageUrl));

    if (!isAlreadyPresent) {
      final updated = [...state.messages, event.message];
      emit(state.copyWith(
        status: ChatDetailStatus.success,
        messages: updated,
        isOtherUserTyping: false,
      ));
      ChatMessagesCache.set(event.message.conversationId, updated);
      _markMessagesAsRead?.call(event.message.conversationId);
    }
  }



  void _onTypingStatusUpdated(
    ChatTypingStatusUpdated event,
    Emitter<ChatDetailState> emit,
  ) {
    emit(state.copyWith(isOtherUserTyping: event.isTyping));
  }

  void _onReadReceiptsUpdated(
    ChatReadReceiptsUpdated event,
    Emitter<ChatDetailState> emit,
  ) {
    final updated = state.messages.map((m) {
      if (m.isMine && !m.isRead) {
        return ChatMessage(
          id: m.id,
          conversationId: m.conversationId,
          senderId: m.senderId,
          message: m.message,
          createdAt: m.createdAt,
          isMine: m.isMine,
          imageUrl: m.imageUrl,
          isRead: true,
        );
      }
      return m;
    }).toList();

    emit(state.copyWith(messages: updated));
    ChatMessagesCache.set(event.conversationId, updated);
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

    // ⚡ Optimistic UI Update: แสดงข้อความบนหน้าจอทันทีแบบ 0ms ไม่ต้องรอ Server
    final currentUserId = SupabaseConfig.isInitialized
        ? (SupabaseConfig.client.auth.currentUser?.id ?? 'me')
        : 'me';
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimisticMsg = ChatMessage(
      id: tempId,
      conversationId: event.conversationId,
      senderId: currentUserId,
      message: trimmed,
      createdAt: DateTime.now(),
      isMine: true,
      imageUrl: null,
      isRead: false,
    );


    final updatedMessages = [...state.messages, optimisticMsg];
    emit(state.copyWith(
      status: ChatDetailStatus.success,
      messages: updatedMessages,
    ));
    ChatMessagesCache.set(event.conversationId, updatedMessages);

    // ⚡ Direct Realtime Broadcast เพื่อให้ผู้รับได้รับใน 20-30ms
    ChatRemoteDataSource().broadcastDirectMessage(
      conversationId: event.conversationId,
      message: optimisticMsg,
    );

    try {
      await _sendMessage(
        conversationId: event.conversationId,
        message: trimmed,
      );
    } catch (e) {
      final failed = {...state.failedMessageIds, tempId};
      emit(state.copyWith(
        failedMessageIds: failed,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onRetryMessageSent(
    ChatRetryMessageSent event,
    Emitter<ChatDetailState> emit,
  ) async {
    final matches = state.messages.where((m) => m.id == event.tempMessageId);
    if (matches.isEmpty) return;
    final msg = matches.first;

    if (msg.message.isEmpty) return;

    final failed = {...state.failedMessageIds}..remove(event.tempMessageId);
    emit(state.copyWith(failedMessageIds: failed));

    try {
      await _sendMessage(
        conversationId: event.conversationId,
        message: msg.message,
        imageUrl: msg.imageUrl,
      );
    } catch (e) {
      emit(state.copyWith(
        failedMessageIds: {...state.failedMessageIds, event.tempMessageId},
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
          message: event.caption?.trim().isNotEmpty == true
              ? event.caption!.trim()
              : '📷 ส่งรูปภาพ',
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

  Future<void> _onMultipleImagesUploadedAndSent(
    ChatMultipleImagesUploadedAndSent event,
    Emitter<ChatDetailState> emit,
  ) async {
    if (_uploadChatImage == null || event.images.isEmpty) return;
    emit(state.copyWith(isUploadingImage: true));

    try {
      final total = event.images.length;
      for (int i = 0; i < total; i++) {
        final img = event.images[i];
        final imageUrl = await _uploadChatImage(
          conversationId: event.conversationId,
          imageBytes: img.imageBytes,
          fileName: img.fileName,
        );

        if (imageUrl.isNotEmpty) {
          final hasCaption = event.caption != null && event.caption!.trim().isNotEmpty;
          final msgText = (i == total - 1 && hasCaption)
              ? event.caption!.trim()
              : '📷 ส่งรูปภาพ';

          await _sendMessage(
            conversationId: event.conversationId,
            message: msgText,
            imageUrl: imageUrl,
          );
        }
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

  Future<void> _onMessageDeleted(
    ChatMessageDeleted event,
    Emitter<ChatDetailState> emit,
  ) async {
    final updated = state.messages.where((m) => m.id != event.messageId).toList();
    emit(state.copyWith(messages: updated));
    ChatMessagesCache.set(event.conversationId, updated);

    try {
      await ChatRemoteDataSource().deleteMessage(
        messageId: event.messageId,
        conversationId: event.conversationId,
      );
    } catch (_) {}
  }

  Future<void> _onMessageEdited(
    ChatMessageEdited event,
    Emitter<ChatDetailState> emit,
  ) async {
    final updated = state.messages.map((m) {
      if (m.id == event.messageId) {
        return ChatMessage(
          id: m.id,
          conversationId: m.conversationId,
          senderId: m.senderId,
          message: event.newMessage,
          createdAt: m.createdAt,
          isMine: m.isMine,
          imageUrl: m.imageUrl,
          isRead: m.isRead,
        );
      }
      return m;
    }).toList();
    emit(state.copyWith(messages: updated));
    ChatMessagesCache.set(event.conversationId, updated);

    try {
      await ChatRemoteDataSource().editMessage(
        messageId: event.messageId,
        newMessage: event.newMessage,
      );
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    try {
      _roomBroadcastChannel?.unsubscribe();
    } catch (_) {}
    return super.close();
  }
}
