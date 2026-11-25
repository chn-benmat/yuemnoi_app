import 'dart:convert';
import 'package:collection/collection.dart';
import '../../../../core/cache/app_cache.dart';
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/models/chat_message_model.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/item_inquiry_data.dart';
import '../../domain/usecases/fetch_messages_usecase.dart';
import '../../domain/usecases/get_owned_chat_item_ids_usecase.dart';
import '../../domain/usecases/mark_messages_as_read_usecase.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import '../../domain/usecases/stream_messages_usecase.dart';
import '../../domain/usecases/upload_chat_image_usecase.dart';
import '../../../../core/network/supabase_client.dart';
import 'chat_detail_event.dart';
import 'chat_detail_state.dart';

/// เก็บข้อความที่ server ยืนยันแล้ว 50 รายการล่าสุด โดยแยก cache ตามบัญชี
class ChatMessagesCache {
  static String get _userId => SupabaseConfig.isInitialized
      ? SupabaseConfig.client.auth.currentUser?.id ?? ''
      : '';

  static void set(
    String conversationId,
    List<ChatMessage> messages, {
    String? ownerId,
  }) {
    final userId = ownerId ?? _userId;
    if (userId.isEmpty || userId != _userId) return;
    final confirmed = _uniqueMessages(
      messages.where((m) => !m.id.startsWith('temp_')),
    );
    final recent = confirmed.length > 50
        ? confirmed.sublist(confirmed.length - 50)
        : confirmed;
    AppCache.rememberSnapshot(
      'chat',
      conversationId,
      userId,
      recent.map(ChatMessageModel.toJson).toList(),
    );
    unawaited(_persist(conversationId, userId, recent));
  }

  static List<ChatMessage>? peek(
    String conversationId, {
    String? currentUserId,
  }) {
    final userId = currentUserId ?? _userId;
    if (userId.isEmpty) return null;
    return _decodeSnapshot(
      AppCache.readMemorySnapshot('chat', conversationId, userId),
      userId,
    );
  }

  static Future<void> _persist(
    String conversationId,
    String userId,
    List<ChatMessage> messages,
  ) async {
    try {
      await AppCache.database.writeSnapshot(
        'chat',
        conversationId,
        userId,
        messages.map(ChatMessageModel.toJson).toList(),
      );
    } catch (_) {
      // Cache ไม่ควรขัดขวางการรับส่งข้อความกับ server
    }
  }

  static Future<List<ChatMessage>?> loadFromDisk(
    String conversationId, {
    required String currentUserId,
  }) async {
    if (currentUserId.isEmpty) return null;
    final memory = peek(conversationId, currentUserId: currentUserId);
    if (memory != null) return memory;
    final revision = AppCache.scopeRevision(currentUserId);
    try {
      final rows = await AppCache.database.readSnapshot(
        'chat',
        conversationId,
        currentUserId,
      );
      if (revision != AppCache.scopeRevision(currentUserId)) return null;
      if (rows != null)
        AppCache.rememberSnapshot('chat', conversationId, currentUserId, rows);
      return _decodeSnapshot(rows, currentUserId);
    } catch (_) {
      return null;
    }
  }

  static List<ChatMessage>? _decodeSnapshot(
    List<Map<String, dynamic>>? rows,
    String userId,
  ) {
    if (rows == null) return null;
    // แคชจากเวอร์ชันก่อนอาจมีข้อความ ID ซ้ำจาก realtime
    return _uniqueMessages(
      rows.map((row) => ChatMessageModel.fromJson(row, currentUserId: userId)),
    );
  }

  static List<ChatMessage> _uniqueMessages(Iterable<ChatMessage> messages) {
    final seenIds = <String>{};
    return [
      for (final message in messages)
        if (seenIds.add(message.id)) message,
    ];
  }

  static void clear() {
    final userId = _userId;
    if (userId.isNotEmpty) unawaited(AppCache.forgetUser(userId));
  }
}

class _ChatItemOwnershipUpdated extends ChatDetailEvent {
  const _ChatItemOwnershipUpdated(this.itemIds, this.epoch);

  final Set<int> itemIds;
  final int epoch;

  @override
  List<Object?> get props => [itemIds, epoch];
}

class ChatDetailBloc extends Bloc<ChatDetailEvent, ChatDetailState> {
  static const _chatConnectionError =
      'แชตไม่สามารถอัปเดตข้อความอัตโนมัติได้ กรุณาตรวจสอบอินเทอร์เน็ต '
      'แล้วออกจากแชตและเปิดใหม่ หากกำลังทำรายการเช่า '
      'กรุณาตรวจสอบสถานะการเช่าก่อนกดยืนยันอีกครั้ง';

  ChatDetailBloc({
    required StreamMessagesUseCase streamMessages,
    required SendChatMessageUseCase sendMessage,
    FetchMessagesUseCase? fetchMessages,
    UploadChatImageUseCase? uploadChatImage,
    MarkMessagesAsReadUseCase? markMessagesAsRead,
    GetOwnedChatItemIdsUseCase? getOwnedItemIds,
    String? conversationId,
  }) : _streamMessages = streamMessages,
       _conversationId = conversationId,
       _sendMessage = sendMessage,
       _fetchMessages = fetchMessages,
       _uploadChatImage = uploadChatImage,
       _markMessagesAsRead = markMessagesAsRead,
       _getOwnedItemIds = getOwnedItemIds,
       super(_initialState(conversationId)) {
    on<ChatMessagesSubscriptionRequested>(_onSubscriptionRequested);
    on<ChatMessagesUpdated>(_onMessagesUpdated);
    on<ChatMessagesLoadFailed>(
      (event, emit) => emit(
        state.copyWith(
          status: ChatDetailStatus.failure,
          errorMessage: event.message,
        ),
      ),
    );
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
    on<_ChatItemOwnershipUpdated>((event, emit) {
      if (event.epoch != _subscriptionEpoch ||
          _cacheUserId != ChatMessagesCache._userId)
        return;
      emit(
        state.copyWith(ownedItemIds: {...state.ownedItemIds, ...event.itemIds}),
      );
    });
  }

  static ChatDetailState _initialState(String? conversationId) {
    final cached = conversationId == null
        ? null
        : ChatMessagesCache.peek(conversationId);
    return cached == null
        ? const ChatDetailState()
        : ChatDetailState(status: ChatDetailStatus.success, messages: cached);
  }

  final StreamMessagesUseCase _streamMessages;
  final SendChatMessageUseCase _sendMessage;
  final FetchMessagesUseCase? _fetchMessages;
  final UploadChatImageUseCase? _uploadChatImage;
  final MarkMessagesAsReadUseCase? _markMessagesAsRead;
  final GetOwnedChatItemIdsUseCase? _getOwnedItemIds;
  final Set<int> _checkedItemIds = {};
  int? _fallbackItemId;
  String? _conversationId;
  String? _cacheUserId;
  int _subscriptionEpoch = 0;

  @override
  void onChange(Change<ChatDetailState> change) {
    super.onChange(change);
    if (!identical(change.currentState.messages, change.nextState.messages)) {
      unawaited(_resolveItemOwnership(change.nextState.messages));
    }
  }

  Future<void> _resolveItemOwnership(List<ChatMessage> messages) async {
    final getOwnedItemIds = _getOwnedItemIds;
    if (getOwnedItemIds == null) return;
    final itemIds = <int>{
      for (final message in messages)
        if (ItemInquiryData.fromChatMessage(
              message.message,
              defaultItemId: _fallbackItemId,
            )?.itemId
            case final int id)
          if (!_checkedItemIds.contains(id)) id,
    };
    if (itemIds.isEmpty) return;
    final epoch = _subscriptionEpoch;
    _checkedItemIds.addAll(itemIds);
    try {
      final ownedIds = await getOwnedItemIds(itemIds);
      if (!isClosed && epoch == _subscriptionEpoch) {
        add(_ChatItemOwnershipUpdated(ownedIds.intersection(itemIds), epoch));
      }
    } catch (_) {
      // หากตรวจเจ้าของไม่ได้ ให้ซ่อนปุ่มและลองใหม่เมื่อข้อความเปลี่ยน
      if (epoch == _subscriptionEpoch) _checkedItemIds.removeAll(itemIds);
    }
  }

  void _cacheMessages(String conversationId, List<ChatMessage> messages) {
    final ownerId = _cacheUserId;
    if (ownerId == null || ownerId != ChatMessagesCache._userId) return;
    ChatMessagesCache.set(conversationId, messages, ownerId: ownerId);
  }

  bool _isCurrentSubscription(
    String conversationId,
    String userId,
    int epoch,
  ) =>
      !isClosed &&
      _conversationId == conversationId &&
      _subscriptionEpoch == epoch &&
      ChatMessagesCache._userId == userId;

  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  RealtimeChannel? _roomBroadcastChannel;

  Future<void> _onSubscriptionRequested(
    ChatMessagesSubscriptionRequested event,
    Emitter<ChatDetailState> emit,
  ) async {
    _conversationId = event.conversationId;
    final epoch = ++_subscriptionEpoch;
    _fallbackItemId = event.itemId;
    _checkedItemIds.clear();
    emit(state.copyWith(ownedItemIds: const {}));
    final userId = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id ?? ''
        : '';
    _cacheUserId = userId;
    unawaited(_resolveItemOwnership(state.messages));
    final cached = await ChatMessagesCache.loadFromDisk(
      event.conversationId,
      currentUserId: userId,
    );
    if (emit.isDone ||
        !_isCurrentSubscription(event.conversationId, userId, epoch))
      return;
    if (cached != null && cached.isNotEmpty && state.messages.isEmpty) {
      emit(state.copyWith(status: ChatDetailStatus.success, messages: cached));
    }

    await _messagesSubscription?.cancel();
    try {
      _markMessagesAsRead?.call(event.conversationId);

      _messagesSubscription = _streamMessages(event.conversationId).listen(
        (messages) {
          if (_isCurrentSubscription(event.conversationId, userId, epoch)) {
            add(ChatMessagesUpdated(messages));
          }
        },
        onError: (_) {
          if (_isCurrentSubscription(event.conversationId, userId, epoch)) {
            add(const ChatMessagesLoadFailed(_chatConnectionError));
          }
        },
      );

      // ⚡ Direct Realtime Room Broadcast (WebSocket Direct Delivery & Typing & Read)
      if (SupabaseConfig.isInitialized) {
        try {
          final client = SupabaseConfig.client;
          final currentUserId = client.auth.currentUser?.id ?? '';
          _roomBroadcastChannel?.unsubscribe();
          _roomBroadcastChannel = client.channel(
            'chat_room:${event.conversationId}',
          );

          _roomBroadcastChannel?.onBroadcast(
            event: 'new_message',
            callback: (payload) {
              if (!_isCurrentSubscription(event.conversationId, userId, epoch))
                return;
              try {
                final raw = payload['payload'];
                final Map<String, dynamic> msgMap = raw is Map<String, dynamic>
                    ? raw
                    : payload;
                if (msgMap.isNotEmpty) {
                  final incoming = ChatMessageModel.fromJson(
                    msgMap,
                    currentUserId: currentUserId,
                  );
                  if (!incoming.isMine) {
                    add(ChatDirectMessageReceived(incoming));
                  }
                }
              } catch (_) {}
            },
          );

          _roomBroadcastChannel?.onBroadcast(
            event: 'typing',
            callback: (payload) {
              if (!_isCurrentSubscription(event.conversationId, userId, epoch))
                return;
              try {
                final isTyping = payload['is_typing'] as bool? ?? false;
                final senderUid = payload['user_id'] as String?;
                if (senderUid != currentUserId) {
                  add(ChatTypingStatusUpdated(isTyping));
                }
              } catch (_) {}
            },
          );

          _roomBroadcastChannel?.onBroadcast(
            event: 'messages_read',
            callback: (payload) {
              if (!_isCurrentSubscription(event.conversationId, userId, epoch))
                return;
              try {
                final readerId = payload['reader_id'] as String?;
                if (readerId != currentUserId) {
                  add(ChatReadReceiptsUpdated(event.conversationId));
                }
              } catch (_) {}
            },
          );

          _roomBroadcastChannel?.onBroadcast(
            event: 'message_deleted',
            callback: (payload) {
              if (!_isCurrentSubscription(event.conversationId, userId, epoch))
                return;
              try {
                final raw = payload['payload'];
                final Map<String, dynamic> data = raw is Map<String, dynamic>
                    ? raw
                    : payload;
                final deletedId = data['message_id']?.toString() ?? '';
                if (deletedId.isNotEmpty) {
                  add(
                    ChatMessageDeleted(
                      conversationId: event.conversationId,
                      messageId: deletedId,
                    ),
                  );
                }
              } catch (_) {}
            },
          );

          _roomBroadcastChannel?.subscribe();
        } catch (_) {}
      }
    } catch (_) {
      emit(
        state.copyWith(
          status: ChatDetailStatus.failure,
          errorMessage: _chatConnectionError,
        ),
      );
    }
  }

  bool _sameOutgoingMessage(ChatMessage a, ChatMessage b) {
    if (a.conversationId != b.conversationId || a.imageUrl != b.imageUrl)
      return false;
    if (a.message.trim() == b.message.trim()) return true;
    Map<String, dynamic>? metadata(String text) {
      const tag = '[BOOKING_DATA:';
      final start = text.indexOf(tag);
      final end = text.lastIndexOf(']');
      if (start < 0 || end <= start) return null;
      try {
        final data =
            jsonDecode(text.substring(start + tag.length, end))
                as Map<String, dynamic>;
        // Trigger เติมสถานะและข้อมูลจุดนัดรับจาก snapshot หลังบันทึก
        for (final key in [
          'status',
          'bookingId',
          'originalMessageId',
          'latitude',
          'longitude',
          'location',
          'defaultLocation',
          'locationAddress',
          'locationNote',
          'ownerId',
          'conversationId',
        ]) {
          data.remove(key);
        }
        return data;
      } catch (_) {
        return null;
      }
    }

    final left = metadata(a.message);
    final right = metadata(b.message);
    return left != null &&
        right != null &&
        const DeepCollectionEquality().equals(left, right);
  }

  void _onMessagesUpdated(
    ChatMessagesUpdated event,
    Emitter<ChatDetailState> emit,
  ) {
    if (_cacheUserId != null && _cacheUserId != ChatMessagesCache._userId)
      return;
    if (event.messages.isEmpty && _conversationId != null) {
      _cacheMessages(_conversationId!, const []);
    }
    if (event.messages.isNotEmpty) {
      _cacheMessages(event.messages.first.conversationId, event.messages);
      final unreadIncoming = event.messages.any((m) => !m.isMine && !m.isRead);
      if (unreadIncoming) {
        _markMessagesAsRead?.call(event.messages.first.conversationId);
      }
    }

    final pendingOptimistic = state.messages
        .where(
          (m) =>
              m.isMine &&
              m.id.startsWith('temp_') &&
              !event.messages.any(
                (saved) => saved.isMine && _sameOutgoingMessage(m, saved),
              ),
        )
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

    emit(
      state.copyWith(
        status: ChatDetailStatus.success,
        messages: mergedMessages,
      ),
    );
  }

  void _onDirectMessageReceived(
    ChatDirectMessageReceived event,
    Emitter<ChatDetailState> emit,
  ) {
    if (event.message.isMine) return;

    final isAlreadyPresent = state.messages.any(
      (m) =>
          m.id == event.message.id ||
          (!m.id.startsWith('temp_') &&
              m.senderId == event.message.senderId &&
              m.message.trim() == event.message.message.trim() &&
              m.imageUrl == event.message.imageUrl),
    );

    if (!isAlreadyPresent) {
      final updated = [...state.messages, event.message];
      emit(
        state.copyWith(
          status: ChatDetailStatus.success,
          messages: updated,
          isOtherUserTyping: false,
        ),
      );
      _cacheMessages(event.message.conversationId, updated);
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
    _cacheMessages(event.conversationId, updated);
  }

  Future<void> _onOlderMessagesRequested(
    ChatOlderMessagesRequested event,
    Emitter<ChatDetailState> emit,
  ) async {
    if (_fetchMessages == null ||
        state.isFetchingOlder ||
        state.hasReachedMax) {
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
        emit(state.copyWith(isFetchingOlder: false, hasReachedMax: true));
        return;
      }

      // Prepend older messages before existing messages
      final existingIds = state.messages.map((m) => m.id).toSet();
      final newOlder = olderMessages
          .where((m) => !existingIds.contains(m.id))
          .toList();

      emit(
        state.copyWith(
          isFetchingOlder: false,
          hasReachedMax: olderMessages.length < 25,
          messages: [...newOlder, ...state.messages],
        ),
      );
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
    if (trimmed.contains('[BOOKING_DATA:')) {
      if (state.messages.any(
        (m) =>
            m.isMine &&
            m.message.trim() == trimmed &&
            !state.failedMessageIds.contains(m.id),
      ))
        return;
    }

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
      imageUrl: event.imageUrl,
      isRead: false,
    );

    final updatedMessages = [...state.messages, optimisticMsg];
    emit(
      state.copyWith(
        status: ChatDetailStatus.success,
        messages: updatedMessages,
        sendingMessageIds: {...state.sendingMessageIds, tempId},
      ),
    );
    _cacheMessages(event.conversationId, updatedMessages);

    // ⚡ Direct Realtime Broadcast เพื่อให้ผู้รับได้รับใน 20-30ms
    ChatRemoteDataSource().broadcastDirectMessage(
      conversationId: event.conversationId,
      message: optimisticMsg,
    );

    try {
      await _sendMessage(
        conversationId: event.conversationId,
        message: trimmed,
        imageUrl: event.imageUrl,
      );
      emit(
        state.copyWith(
          sendingMessageIds: {...state.sendingMessageIds}..remove(tempId),
        ),
      );
    } catch (e) {
      final failed = {...state.failedMessageIds, tempId};
      emit(
        state.copyWith(
          failedMessageIds: failed,
          sendingMessageIds: {...state.sendingMessageIds}..remove(tempId),
          errorMessage: e.toString(),
        ),
      );
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
    emit(
      state.copyWith(
        failedMessageIds: failed,
        sendingMessageIds: {...state.sendingMessageIds, event.tempMessageId},
      ),
    );

    try {
      await _sendMessage(
        conversationId: event.conversationId,
        message: msg.message,
        imageUrl: msg.imageUrl,
      );
      emit(
        state.copyWith(
          sendingMessageIds: {...state.sendingMessageIds}
            ..remove(event.tempMessageId),
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          failedMessageIds: {...state.failedMessageIds, event.tempMessageId},
          sendingMessageIds: {...state.sendingMessageIds}
            ..remove(event.tempMessageId),
          errorMessage: e.toString(),
        ),
      );
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
      emit(
        state.copyWith(
          isUploadingImage: false,
          status: ChatDetailStatus.failure,
          errorMessage: 'อัปโหลดรูปภาพไม่สำเร็จ: ${e.toString()}',
        ),
      );
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
          final hasCaption =
              event.caption != null && event.caption!.trim().isNotEmpty;
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
      emit(
        state.copyWith(
          isUploadingImage: false,
          status: ChatDetailStatus.failure,
          errorMessage: 'อัปโหลดรูปภาพไม่สำเร็จ: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onMessageDeleted(
    ChatMessageDeleted event,
    Emitter<ChatDetailState> emit,
  ) async {
    final targetMsg = state.messages
        .where((m) => m.id == event.messageId)
        .firstOrNull;
    final imageUrl = targetMsg?.imageUrl ?? event.imageUrl;

    final updated = state.messages
        .where((m) => m.id != event.messageId)
        .toList();
    emit(state.copyWith(messages: updated));
    _cacheMessages(event.conversationId, updated);

    // ส่งสัญญาณ Realtime Broadcast แจ้งเตือนห้องแชทให้ลบข้อความนี้ทันที
    unawaited(
      ChatRemoteDataSource().broadcastMessageDeleted(
        conversationId: event.conversationId,
        messageId: event.messageId,
      ),
    );

    try {
      await ChatRemoteDataSource().deleteMessage(
        messageId: event.messageId,
        conversationId: event.conversationId,
        imageUrl: imageUrl,
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
    _cacheMessages(event.conversationId, updated);

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
