import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../booking/domain/entities/booking_request_model.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_reply_content.dart';
import '../../domain/entities/item_inquiry_data.dart';
import '../../domain/usecases/should_send_item_inquiry_usecase.dart';
import '../models/chat_conversation_model.dart';
import '../models/chat_message_model.dart';

class ChatRemoteException implements Exception {
  const ChatRemoteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatRemoteDataSource {
  ChatRemoteDataSource({SupabaseClient? client, ApiClient? apiClient})
    : _client = client,
      _apiClient = apiClient;

  final SupabaseClient? _client;
  ApiClient? _apiClient;
  static const _chatBucket = 'chat_bk';
  static const _conversationItemColumns =
      'id,item_name,item_image_url,hourly_rate,daily_rate,user_id';
  static final _signedImages =
      <
        (SupabaseClient, String, String),
        ({DateTime expiresAt, Future<String> url, String? resolved})
      >{};
  static final _pendingInquiries =
      <(SupabaseClient, String, String, int, bool), Future<String?>>{};
  static final _rentalAvailabilityChanges = Expando<Map<int, Stream<void>>>();

  ApiClient get _backendClient => _apiClient ??= DioApiClient();

  SupabaseClient get _supabaseClient {
    if (_client != null) return _client;
    if (SupabaseConfig.isInitialized) {
      return SupabaseConfig.client;
    }
    throw const ChatRemoteException('ระบบเชื่อมต่อฐานข้อมูลยังไม่พร้อมใช้งาน');
  }

  String get _currentUserId {
    final userId = _supabaseClient.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw const ChatRemoteException('กรุณาเข้าสู่ระบบก่อนใช้งานแชท');
    }
    return userId;
  }

  Future<ChatConversation> getOrCreateConversation({
    int? itemId,
    required String ownerId,
  }) async {
    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    if (currentUserId == ownerId) {
      throw const ChatRemoteException('ไม่สามารถส่งข้อความหาตนเองได้');
    }

    try {
      // 1. ตรวจสอบว่าเคยมีห้องแชทระหว่าง 2 คนนี้หรือไม่ (ไม่ว่าจะทักมาจากอุปกรณ์/สินค้าใด หรือทิศทางใด)
      final existingConvs = await client
          .schema('messaging')
          .from('conversation_tb')
          .select('*')
          .or(
            'and(renter_id.eq.$currentUserId,owner_id.eq.$ownerId),and(renter_id.eq.$ownerId,owner_id.eq.$currentUserId)',
          )
          .order('last_message_at', ascending: false)
          .limit(1);

      Map<String, dynamic>? conversation;
      if (existingConvs.isNotEmpty) {
        conversation = (existingConvs.first as Map).cast<String, dynamic>();
        // อัปเดต item_id เป็นอุปกรณ์ล่าสุดที่กดทักมา (ถ้ามีการระบุ itemId)
        if (itemId != null && itemId > 0) {
          try {
            await client
                .schema('messaging')
                .from('conversation_tb')
                .update({'item_id': itemId})
                .eq('id', conversation['id']);
            conversation['item_id'] = itemId;
          } catch (_) {}
        }
      }

      // 2. ถ้ายังไม่เคยมีห้องแชทระหว่าง 2 คนนี้เลย ให้สร้างห้องใหม่
      if (conversation == null) {
        final Map<String, dynamic> insertData = {
          'renter_id': currentUserId,
          'owner_id': ownerId,
          'last_message': '',
          'last_message_at': DateTime.now().toUtc().toIso8601String(),
        };
        if (itemId != null && itemId > 0) {
          insertData['item_id'] = itemId;
        }

        conversation = await client
            .schema('messaging')
            .from('conversation_tb')
            .insert(insertData)
            .select('*')
            .single();
      }

      // 3. ดึงข้อมูลโปรไฟล์ของคู่สนทนา (เจ้าของอุปกรณ์ / ผู้ใช้ที่สนทนาด้วย) ผ่าน secure view
      final otherProfile = await client
          .schema('profiles')
          .from('public_profile_v')
          .select('user_id,user_image_url,is_online,last_seen_at,display_name')
          .eq('user_id', ownerId)
          .maybeSingle();

      // 4. ดึงข้อมูลอุปกรณ์ (หากมีการผูก item_id ไว้)
      final dynamic effectiveItemId =
          conversation['item_id'] ??
          (itemId != null && itemId > 0 ? itemId : null);
      Map<String, dynamic>? item;
      if (effectiveItemId != null) {
        final parsedId = effectiveItemId is num
            ? effectiveItemId.toInt()
            : int.tryParse(effectiveItemId.toString());
        if (parsedId != null && parsedId > 0) {
          item = await client
              .from('item_tb')
              .select(_conversationItemColumns)
              .eq('id', parsedId)
              .maybeSingle();
        }
      }

      final result = ChatConversationModel.fromRecords(
        conversation: conversation,
        otherProfile: otherProfile,
        item: item,
        currentUserId: currentUserId,
      );
      // เมื่อกดสอบถามจากสินค้า ผู้ใช้เป็นผู้เช่าของสินค้าที่เพิ่งเลือก
      return itemId != null && itemId > 0
          ? result.copyWith(itemRentalRole: ChatParticipantRole.renter)
          : result;
    } on ChatRemoteException {
      rethrow;
    } on PostgrestException catch (e) {
      throw ChatRemoteException('เกิดข้อผิดพลาดในการโหลดห้องแชท: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException(
        'ไม่สามารถเชื่อมต่อห้องแชทได้ กรุณาลองใหม่',
      );
    }
  }

  Future<ChatConversation?> getConversationById(String conversationId) async {
    if (!SupabaseConfig.isInitialized && _client == null) return null;
    if (conversationId.isEmpty) return null;

    try {
      final client = _supabaseClient;
      final currentUserId = _currentUserId;

      final conv = await client
          .schema('messaging')
          .from('conversation_tb')
          .select('*')
          .eq('id', conversationId)
          .maybeSingle();

      if (conv == null) return null;

      final renterId = conv['renter_id']?.toString() ?? '';
      final ownerId = conv['owner_id']?.toString() ?? '';
      final otherId = currentUserId == renterId ? ownerId : renterId;

      Map<String, dynamic>? otherProfile;
      if (otherId.isNotEmpty) {
        otherProfile = await client
            .schema('profiles')
            .from('public_profile_v')
            .select(
              'user_id,user_image_url,is_online,last_seen_at,display_name',
            )
            .eq('user_id', otherId)
            .maybeSingle();
      }

      Map<String, dynamic>? item;
      if (conv['item_id'] != null) {
        final itemId = conv['item_id'] is num
            ? (conv['item_id'] as num).toInt()
            : int.tryParse(conv['item_id'].toString());
        if (itemId != null) {
          item = await client
              .from('item_tb')
              .select(_conversationItemColumns)
              .eq('id', itemId)
              .maybeSingle();
        }
      }

      return ChatConversationModel.fromRecords(
        conversation: conv,
        otherProfile: otherProfile,
        item: item,
        currentUserId: currentUserId,
      );
    } catch (e) {
      debugPrint('getConversationById error: $e');
      return null;
    }
  }

  Future<Set<int>> getOwnedItemIds(Set<int> itemIds) async {
    if (itemIds.isEmpty) return {};
    if (!SupabaseConfig.isInitialized && _client == null) return {};
    final userId = _currentUserId;
    final rows = await _supabaseClient
        .from('item_tb')
        .select('id')
        .eq('user_id', userId)
        .inFilter('id', itemIds.toList(growable: false));
    return {
      for (final row in rows)
        if (int.tryParse(row['id'].toString()) case final int id) id,
    };
  }

  Future<Set<int>> getUnavailableRentalItemIds(Set<int> itemIds) async {
    if (itemIds.isEmpty || (!SupabaseConfig.isInitialized && _client == null)) {
      return {};
    }
    final rows = await _supabaseClient
        .from('item_tb')
        .select('id,is_rental_occupied,is_rental_queue_held')
        .inFilter('id', itemIds.toList(growable: false));
    return {
      for (final row in rows)
        if (row['is_rental_occupied'] == true ||
            row['is_rental_queue_held'] == true)
          if (row['id'] case final int id) id,
    };
  }

  Stream<void> watchRentalAvailabilityChanges(int itemId) {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const Stream.empty();
    }
    final client = _supabaseClient;
    final streams = _rentalAvailabilityChanges[client] ??= {};
    return streams.putIfAbsent(itemId, () {
      RealtimeChannel? channel;
      late final StreamController<void> changes;
      changes = StreamController<void>.broadcast(
        onListen: () {
          final subscription = client.channel(
            'chat_rental_item:$itemId',
            opts: const RealtimeChannelConfig(private: true),
          );
          channel = subscription;

          void notifyChanged() {
            if (channel == subscription) changes.add(null);
          }

          subscription
              .onBroadcast(
                event: 'rental_availability_changed',
                callback: (_) => notifyChanged(),
              )
              .subscribe((status, _) {
                // โหลดสถานะหลังเชื่อมต่อเผื่อมีการเปลี่ยนแปลงระหว่างที่หลุด
                if (status == RealtimeSubscribeStatus.subscribed) {
                  notifyChanged();
                }
              });
        },
        onCancel: () {
          final subscription = channel;
          channel = null;
          streams.remove(itemId);
          if (subscription != null) {
            unawaited(client.removeChannel(subscription));
          }
        },
      );
      return changes.stream;
    });
  }

  Future<List<ChatConversation>> getConversations() async {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const [];
    }

    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    try {
      final rawConversations = await client
          .schema('messaging')
          .from('conversation_tb')
          .select('*')
          .or('renter_id.eq.$currentUserId,owner_id.eq.$currentUserId')
          .order('last_message_at', ascending: false);

      final allRawConversations = (rawConversations as List)
          .cast<Map<String, dynamic>>();
      if (allRawConversations.isEmpty) return const [];

      // Deduplicate: รวมห้องแชทของคู่สนทนาคนเดียวกัน ให้แสดงเฉพาะห้องแชทล่าสุดเพียงห้องเดียว
      final conversations = <Map<String, dynamic>>[];
      final seenOtherUserIds = <String>{};
      for (final conv in allRawConversations) {
        final renterId = conv['renter_id']?.toString() ?? '';
        final ownerId = conv['owner_id']?.toString() ?? '';
        final otherId = currentUserId == renterId ? ownerId : renterId;
        if (otherId.isEmpty || seenOtherUserIds.add(otherId)) {
          conversations.add(conv);
        }
      }

      // รวบรวม ID ของคู่สนทนาและ item_id ทั้งหมดเพื่อ query ครั้งเดียว
      final otherUserIds = <String>{};
      final itemIds = <int>{};

      for (final conv in conversations) {
        final renterId = conv['renter_id']?.toString() ?? '';
        final ownerId = conv['owner_id']?.toString() ?? '';
        final otherId = currentUserId == renterId ? ownerId : renterId;
        if (otherId.isNotEmpty) otherUserIds.add(otherId);

        if (conv['item_id'] != null) {
          final parsed = conv['item_id'] is num
              ? (conv['item_id'] as num).toInt()
              : int.tryParse(conv['item_id'].toString());
          if (parsed != null) itemIds.add(parsed);
        }
      }

      final conversationIds = conversations
          .map((conversation) => conversation['id']?.toString())
          .whereType<String>()
          .toList(growable: false);
      final (
        (profilesMap, profileLookupSucceeded),
        itemsMap,
        unreadConvIds,
      ) = await (
        _loadConversationProfiles(client, otherUserIds),
        _loadConversationItems(client, itemIds),
        _loadUnreadConversationIds(client, conversationIds),
      ).wait;

      return conversations
          .map((conv) {
            final convId = conv['id']?.toString() ?? '';
            final renterId = conv['renter_id']?.toString() ?? '';
            final ownerId = conv['owner_id']?.toString() ?? '';
            final otherId = currentUserId == renterId ? ownerId : renterId;

            int? itemId;
            if (conv['item_id'] != null) {
              itemId = conv['item_id'] is num
                  ? (conv['item_id'] as num).toInt()
                  : int.tryParse(conv['item_id'].toString());
            }

            return ChatConversationModel.fromRecords(
              conversation: conv,
              otherProfile: profilesMap[otherId],
              item: itemId != null ? itemsMap[itemId] : null,
              currentUserId: currentUserId,
              hasUnreadMessage: unreadConvIds.contains(convId),
              profileLookupSucceeded: profileLookupSucceeded,
            );
          })
          .toList(growable: false);
    } on ChatRemoteException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('getConversations PostgrestException: ${e.message}');
      throw ChatRemoteException('โหลดรายการแชทไม่สำเร็จ: ${e.message}');
    } catch (e, stack) {
      debugPrint('getConversations error: $e\n$stack');
      throw const ChatRemoteException('ไม่สามารถดึงข้อมูลแชทได้ กรุณาลองใหม่');
    }
  }

  Future<(Map<String, Map<String, dynamic>>, bool)> _loadConversationProfiles(
    SupabaseClient client,
    Set<String> otherUserIds,
  ) async {
    final profilesMap = <String, Map<String, dynamic>>{};
    if (otherUserIds.isEmpty) return (profilesMap, true);

    try {
      final profiles = await client
          .schema('profiles')
          .from('public_profile_v')
          .select('user_id,user_image_url,is_online,last_seen_at,display_name')
          .inFilter('user_id', otherUserIds.toList(growable: false));
      for (final profile in profiles) {
        final userId = profile['user_id']?.toString();
        if (userId != null) profilesMap[userId] = profile;
      }
      return (profilesMap, true);
    } catch (e) {
      debugPrint('getConversations profiles sub-query error: $e');
      return (profilesMap, false);
    }
  }

  Future<Map<int, Map<String, dynamic>>> _loadConversationItems(
    SupabaseClient client,
    Set<int> itemIds,
  ) async {
    final itemsMap = <int, Map<String, dynamic>>{};
    if (itemIds.isEmpty) return itemsMap;

    try {
      final items = await client
          .from('item_tb')
          .select(_conversationItemColumns)
          .inFilter('id', itemIds.toList(growable: false));
      for (final item in items) {
        final rawId = item['id'];
        final id = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId.toString());
        if (id != null) itemsMap[id] = item;
      }
    } catch (e) {
      debugPrint('getConversations items sub-query error: $e');
    }
    return itemsMap;
  }

  Future<Set<String>> _loadUnreadConversationIds(
    SupabaseClient client,
    List<String> conversationIds,
  ) async {
    if (conversationIds.isEmpty) return const {};

    try {
      final rows = await client
          .schema('public')
          .rpc<PostgrestList>(
            'chat_unread_conversation_ids',
            params: {'p_conversation_ids': conversationIds},
          );
      return rows
          .map((row) => row['conversation_id']?.toString())
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('getConversations unread sub-query error: $e');
      return const {};
    }
  }

  Future<String> getConversationContactPhone(String conversationId) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const ChatRemoteException('กรุณาเข้าสู่ระบบก่อนดูข้อมูลติดต่อ');
    }

    try {
      final response = await _backendClient.post(
        '/api/chat/contact',
        data: {'conversation_id': conversationId},
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = response.data;
      final phone = data['phone']?.toString().trim() ?? '';
      if (phone.isNotEmpty) {
        return phone;
      }

      final message = data['error']?.toString().trim() ?? '';
      throw ChatRemoteException(
        message.isEmpty ? 'ไม่สามารถโหลดเบอร์โทรศัพท์ได้' : message,
      );
    } on ChatRemoteException {
      rethrow;
    } on ApiClientException catch (error) {
      switch (error.type) {
        case ApiClientErrorType.timeout:
          throw const ChatRemoteException(
            'โหลดเบอร์โทรศัพท์นานเกินไป กรุณาลองใหม่',
          );
        case ApiClientErrorType.connection:
          throw const ChatRemoteException('ไม่สามารถเชื่อมต่อระบบติดต่อได้');
        case ApiClientErrorType.invalidResponse:
          throw const ChatRemoteException(
            'ระบบติดต่อส่งข้อมูลกลับมาไม่ถูกต้อง',
          );
      }
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการโหลดเบอร์โทรศัพท์');
    }
  }

  Stream<List<ChatConversation>> streamConversations() {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const Stream.empty();
    }

    final client = _supabaseClient;
    return client
        .schema('messaging')
        .from('conversation_tb')
        .stream(primaryKey: ['id'])
        .asyncMap((_) async {
          try {
            return await getConversations();
          } catch (_) {
            return <ChatConversation>[];
          }
        })
        .handleError((error) {
          debugPrint('streamConversations connection error: $error');
        });
  }

  Future<void> markMessagesAsRead({required String conversationId}) async {
    if (!SupabaseConfig.isInitialized && _client == null) return;
    if (conversationId.isEmpty) return;
    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    try {
      await client
          .schema('messaging')
          .from('chat_message_tb')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .or('sender_id.neq.$currentUserId,sender_id.is.null')
          .not('is_read', 'is', true);
      // Trigger ซิงก์ประวัติแจ้งเตือนให้ทุกเครื่องจากสถานะอ่านของข้อความจริง
    } catch (_) {}
  }

  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    DateTime? before,
    int limit = 25,
  }) async {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const [];
    }

    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    try {
      var query = client
          .schema('messaging')
          .from('chat_message_tb')
          .select('*')
          .eq('conversation_id', conversationId);

      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }

      final records = await query
          .order('created_at', ascending: false)
          .limit(limit);

      final list = records
          .map((json) => _messageWithCachedImages(json, currentUserId))
          .toList();
      // รีเฟรชลิงก์รูปคู่ขนาน ไม่ให้ข้อความและการเลื่อนประวัติรอเครือข่ายรูป
      unawaited(
        Future.wait(
          records.map((json) => _messageWithFreshImages(json, currentUserId)),
        ),
      );

      // Return messages in chronological order (oldest to newest)
      return list.reversed.toList(growable: false);
    } on PostgrestException catch (e) {
      throw ChatRemoteException('โหลดข้อความไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการโหลดข้อความ');
    }
  }

  Stream<List<ChatMessage>> streamMessages(String conversationId) {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const Stream.empty();
    }

    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    final recordsStream = client
        .schema('messaging')
        .from('chat_message_tb')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return Stream<List<ChatMessage>>.multi((controller) {
      var active = true;
      var revision = 0;
      var latestMessages = <ChatMessage>[];
      var bookingIds = <int>{};
      var bookingStatuses = <int, String>{};
      StreamSubscription<List<Map<String, dynamic>>>? bookingsSubscription;

      void emitMessages() {
        if (!active) return;
        controller.add(
          latestMessages.map((message) {
            final booking = BookingRequestData.fromChatMessage(message.message);
            final status = bookingStatuses[booking?.bookingId];
            if (booking == null ||
                status == null ||
                (status == 'pending' && booking.status == 'confirmed')) {
              return message;
            }
            return ChatMessage(
              id: message.id,
              conversationId: message.conversationId,
              senderId: message.senderId,
              message: booking.copyWith(status: status).toChatMessagePayload(),
              createdAt: message.createdAt,
              isMine: message.isMine,
              imageUrl: message.imageUrl,
              isRead: message.isRead,
            );
          }).toList(),
        );
      }

      final subscription = recordsStream.listen(
        (records) {
          final currentRevision = ++revision;
          final immediate = records
              .map((record) => _messageWithCachedImages(record, currentUserId))
              .toList();
          latestMessages = immediate;
          emitMessages();
          final ids = immediate
              .map(
                (m) => BookingRequestData.fromChatMessage(m.message)?.bookingId,
              )
              .whereType<int>()
              .where((id) => id > 0)
              .toSet();
          if (!setEquals(ids, bookingIds)) {
            bookingIds = ids;
            unawaited(bookingsSubscription?.cancel());
            if (ids.isNotEmpty) {
              // ใช้สถานะของการจองจริง เพื่อให้การคืนเปลี่ยนแชทได้โดยไม่ต้องมีข้อความใหม่
              final watchedIds = ids;
              bookingsSubscription = client
                  .from('booking_tb')
                  .stream(primaryKey: ['id'])
                  .inFilter('id', ids.toList())
                  .listen((rows) {
                    if (!active || !setEquals(watchedIds, bookingIds)) return;
                    bookingStatuses = {
                      for (final row in rows)
                        (row['id'] as num).toInt(): row['status'].toString(),
                    };
                    emitMessages();
                  }, onError: controller.addError);
            }
          }
          // ข้อความใหม่ต้องผ่านได้ แม้การรีเฟรชรูปของชุดก่อนยังไม่เสร็จ
          unawaited(
            Future.wait(
              records.map(
                (record) => _messageWithFreshImages(record, currentUserId),
              ),
            ).then((fresh) {
              if (active &&
                  currentRevision == revision &&
                  !listEquals(immediate, fresh)) {
                latestMessages = fresh;
                emitMessages();
              }
            }),
          );
        },
        onError: controller.addError,
        onDone: () {
          active = false;
          unawaited(bookingsSubscription?.cancel());
          controller.close();
        },
      );
      controller.onPause = subscription.pause;
      controller.onResume = subscription.resume;
      controller.onCancel = () async {
        active = false;
        await bookingsSubscription?.cancel();
        await subscription.cancel();
      };
    });
  }

  ChatMessage _messageWithCachedImages(
    Map<String, dynamic> record,
    String userId,
  ) {
    final message = ChatMessageModel.fromJson(record, currentUserId: userId);
    final reply = ChatReplyContent.tryParse(message.message);
    String? cached(String? url) {
      if (url == null) return null;
      final uri = Uri.tryParse(url);
      const prefix = '/storage/v1/object/sign/chat_bk/';
      if (uri == null || !uri.path.startsWith(prefix)) return url;
      if (uri.origin !=
          Uri.parse(
            _supabaseClient.storage.from(_chatBucket).getPublicUrl(''),
          ).origin)
        return url;
      final path = Uri.decodeComponent(uri.path.substring(prefix.length));
      final entry = _signedImages[(_supabaseClient, userId, path)];
      return entry != null && entry.expiresAt.isAfter(DateTime.now())
          ? entry.resolved ?? url
          : url;
    }

    return _replaceMessageImages(
      message,
      cached(message.imageUrl),
      cached(reply?.quotedImageUrl),
    );
  }

  Future<ChatMessage> _messageWithFreshImages(
    Map<String, dynamic> record,
    String currentUserId,
  ) async {
    final message = ChatMessageModel.fromJson(
      record,
      currentUserId: currentUserId,
    );
    final reply = ChatReplyContent.tryParse(message.message);
    final images = await Future.wait([
      _freshImageUrl(message.imageUrl, message.conversationId, currentUserId),
      _freshImageUrl(
        reply?.quotedImageUrl,
        message.conversationId,
        currentUserId,
      ),
    ]);
    return _replaceMessageImages(message, images[0], images[1]);
  }

  ChatMessage _replaceMessageImages(
    ChatMessage message,
    String? imageUrl,
    String? quotedImageUrl,
  ) {
    final reply = ChatReplyContent.tryParse(message.message);
    final refreshedReply =
        reply != null && quotedImageUrl != reply.quotedImageUrl
        ? ChatReplyContent(
            target: reply.target,
            quotedText: reply.quotedText,
            quotedMessageId: reply.quotedMessageId,
            quotedImageUrl: quotedImageUrl,
            text: reply.text,
          ).toMessage()
        : message.message;
    return ChatMessage(
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      message: refreshedReply,
      createdAt: message.createdAt,
      isMine: message.isMine,
      isRead: message.isRead,
      imageUrl: imageUrl,
    );
  }

  Future<String> refreshChatImageUrl(String imageUrl) async {
    if (!SupabaseConfig.isInitialized && _client == null) return imageUrl;
    final uri = Uri.tryParse(imageUrl);
    const prefix = '/storage/v1/object/sign/chat_bk/';
    if (uri == null || !uri.path.startsWith(prefix)) return imageUrl;
    final segments = Uri.decodeComponent(
      uri.path.substring(prefix.length),
    ).split('/');
    if (segments.length < 2) return imageUrl;
    return await _freshImageUrl(
          imageUrl,
          segments[segments.length - 2],
          _currentUserId,
        ) ??
        imageUrl;
  }

  Future<String?> _freshImageUrl(
    String? imageUrl,
    String conversationId,
    String currentUserId,
  ) async {
    if (imageUrl == null) return null;
    final uri = Uri.tryParse(imageUrl);
    const prefix = '/storage/v1/object/sign/chat_bk/';
    if (uri == null || !uri.path.startsWith(prefix)) return imageUrl;

    try {
      final bucket = _supabaseClient.storage.from(_chatBucket);
      final storageOrigin = Uri.parse(bucket.getPublicUrl('')).origin;
      if (uri.origin != storageOrigin) return imageUrl;
      final path = Uri.decodeComponent(uri.path.substring(prefix.length));
      final segments = path.split('/');
      // รูปเก่าใช้ senderId/conversationId/file ส่วนรูปใหม่ใช้ conversationId/file
      final belongsToConversation =
          (segments.length == 2 && segments.first == conversationId) ||
          (segments.length == 3 && segments[1] == conversationId);
      if (!belongsToConversation || segments.contains('..')) return imageUrl;
      final now = DateTime.now();
      // ใช้ลิงก์ที่ยังไม่หมดอายุเพื่อรักษา identity ของข้อความที่กำลังส่ง
      try {
        final token = uri.queryParameters['token'] ?? '';
        final claims =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(base64Url.normalize(token.split('.')[1])),
                  ),
                )
                as Map<String, dynamic>;
        final expires = claims['exp'];
        if (expires is num && expires > now.millisecondsSinceEpoch ~/ 1000 + 60)
          return imageUrl;
      } catch (_) {}

      // ข้อความเก่าเก็บ signed URL อายุหนึ่งชั่วโมงไว้ จึงต้องลงนามใหม่ก่อนแสดง
      _signedImages.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
      final key = (_supabaseClient, currentUserId, path);
      final entry = _signedImages.putIfAbsent(
        key,
        () => (
          expiresAt: now.add(const Duration(minutes: 55)),
          url: bucket.createSignedUrl(path, 3600),
          resolved: null,
        ),
      );
      try {
        final resolved = await entry.url;
        _signedImages[key] = (
          expiresAt: entry.expiresAt,
          url: entry.url,
          resolved: resolved,
        );
        return resolved;
      } catch (_) {
        _signedImages.remove(key);
        return imageUrl;
      }
    } catch (_) {
      // ความผิดพลาดของรูปไม่ควรทำให้ประวัติข้อความทั้งห้องหายไป
      return imageUrl;
    }
  }

  RealtimeChannel? _roomChannel;
  String? _activeRoomChannelConversationId;

  RealtimeChannel? getOrCreateRoomChannel(String conversationId) {
    if (!SupabaseConfig.isInitialized && _client == null) return null;
    if (_roomChannel != null &&
        _activeRoomChannelConversationId == conversationId) {
      return _roomChannel;
    }
    try {
      _roomChannel?.unsubscribe();
    } catch (_) {}
    _activeRoomChannelConversationId = conversationId;
    _roomChannel = _supabaseClient.channel('chat_room:$conversationId');
    return _roomChannel;
  }

  Future<void> broadcastDirectMessage({
    required String conversationId,
    required ChatMessage message,
  }) async {
    try {
      final channel = getOrCreateRoomChannel(conversationId);
      final currentUserId = _supabaseClient.auth.currentUser?.id ?? '';
      final payload = ChatMessageModel.toJson(message);
      if (currentUserId.isNotEmpty) {
        payload['sender_id'] = currentUserId;
      }
      payload.remove('is_mine');
      await channel?.sendBroadcastMessage(
        event: 'new_message',
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> broadcastTypingStatus({
    required String conversationId,
    required bool isTyping,
  }) async {
    try {
      final channel = getOrCreateRoomChannel(conversationId);
      await channel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': _currentUserId, 'is_typing': isTyping},
      );
    } catch (_) {}
  }

  Future<void> broadcastReadReceipt({required String conversationId}) async {
    try {
      final channel = getOrCreateRoomChannel(conversationId);
      await channel?.sendBroadcastMessage(
        event: 'messages_read',
        payload: {
          'reader_id': _currentUserId,
          'conversation_id': conversationId,
        },
      );
    } catch (_) {}
  }

  Future<void> broadcastMessageDeleted({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      final channel = getOrCreateRoomChannel(conversationId);
      await channel?.sendBroadcastMessage(
        event: 'message_deleted',
        payload: {'message_id': messageId, 'conversation_id': conversationId},
      );
    } catch (_) {}
  }

  Future<String> uploadChatImage({
    required String conversationId,
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    final client = _supabaseClient;
    final currentUserId = _currentUserId;
    final extension = _extension(fileName);
    final path =
        '$conversationId/$currentUserId-${DateTime.now().microsecondsSinceEpoch}.$extension';

    try {
      await client.storage
          .from(_chatBucket)
          .uploadBinary(
            path,
            imageBytes,
            fileOptions: FileOptions(contentType: _contentType(extension)),
          );
      // สร้าง Signed URL สำหรับ bucket ส่วนตัว (chat_bk) มีอายุ 60 นาที (3600 วินาที)
      return await client.storage.from(_chatBucket).createSignedUrl(path, 3600);
    } on StorageException catch (e) {
      throw ChatRemoteException('อัปโหลดรูปภาพไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการอัปโหลดรูปภาพ');
    }
  }

  /// คืน ID ของการ์ดเดิมเมื่อมีอยู่แล้วและไม่ต้องส่งซ้ำ
  Future<String?> sendItemInquiryIfNeeded({
    required String conversationId,
    required ItemInquiryData inquiry,
    String? imageUrl,
    bool onlyIfPickupDeadlineExpired = false,
  }) async {
    final itemId = inquiry.itemId;
    if (itemId == null || itemId <= 0) {
      throw const ChatRemoteException('ไม่พบอุปกรณ์สำหรับเริ่มการสนทนา');
    }
    final userId = _currentUserId;
    final key = (
      _supabaseClient,
      userId,
      conversationId,
      itemId,
      onlyIfPickupDeadlineExpired,
    );
    final pending = _pendingInquiries[key];
    if (pending != null) return pending;

    final operation = _sendItemInquiryIfNeeded(
      conversationId: conversationId,
      userId: userId,
      inquiry: inquiry,
      imageUrl: imageUrl,
      onlyIfPickupDeadlineExpired: onlyIfPickupDeadlineExpired,
    );
    _pendingInquiries[key] = operation;
    try {
      return await operation;
    } on ChatRemoteException {
      rethrow;
    } catch (_) {
      throw const ChatRemoteException(
        'ตรวจสอบการสนทนาเดิมไม่สำเร็จ กรุณาลองใหม่',
      );
    } finally {
      if (identical(_pendingInquiries[key], operation))
        _pendingInquiries.remove(key);
    }
  }

  Future<String?> _sendItemInquiryIfNeeded({
    required String conversationId,
    required String userId,
    required ItemInquiryData inquiry,
    required bool onlyIfPickupDeadlineExpired,
    String? imageUrl,
  }) async {
    Future<List<Map<String, dynamic>>> fetchLatestBooking(String columns) =>
        _supabaseClient
            .from('booking_tb')
            .select(columns)
            .eq('user_id', userId)
            .eq('item_id', inquiry.itemId!)
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .limit(1);

    List<Map<String, dynamic>> bookings;
    try {
      bookings = await fetchLatestBooking('id,status,pickup_deadline_expired');
    } on PostgrestException catch (error) {
      if (error.code != '42703' ||
          !error.message.contains('pickup_deadline_expired')) {
        rethrow;
      }
      // ฐานข้อมูลรุ่นเดิมยังใช้รายการเช่าล่าสุดเพื่อตรวจการส่งซ้ำได้
      bookings = await fetchLatestBooking('id,status');
    }
    final latestBooking = bookings.isEmpty ? null : bookings.first;
    final bookingId = latestBooking == null
        ? null
        : int.tryParse(latestBooking['id'].toString());
    if (latestBooking != null && bookingId == null) {
      throw const ChatRemoteException('ข้อมูลรายการเช่าเดิมไม่ถูกต้อง');
    }
    final pickupDeadlineExpired =
        latestBooking?['status'] == 'cancelled' &&
        latestBooking?['pickup_deadline_expired'] == true;
    if (onlyIfPickupDeadlineExpired && !pickupDeadlineExpired) return null;

    final latestInquiry = await _findLatestItemInquiry(
      conversationId: conversationId,
      userId: userId,
      itemId: inquiry.itemId!,
    );
    if (_currentUserId != userId) {
      throw const ChatRemoteException('บัญชีผู้ใช้เปลี่ยน กรุณาเปิดแชตใหม่');
    }
    final needsNewInquiry = const ShouldSendItemInquiryUseCase()(
      latestInquiry: latestInquiry?.inquiry,
      latestBookingId: bookingId,
      latestBookingStatus: latestBooking?['status']?.toString(),
    );
    if (!needsNewInquiry && !pickupDeadlineExpired) {
      return latestInquiry?.messageId;
    }

    await sendMessage(
      conversationId: conversationId,
      message: inquiry.withPreviousBookingId(bookingId).toChatMessagePayload(),
      imageUrl: imageUrl,
    );
    return needsNewInquiry ? null : latestInquiry?.messageId;
  }

  Future<({String messageId, ItemInquiryData inquiry})?>
  _findLatestItemInquiry({
    required String conversationId,
    required String userId,
    required int itemId,
  }) async {
    const pageSize = 100;
    for (var offset = 0; ; offset += pageSize) {
      final rows = await _supabaseClient
          .schema('messaging')
          .from('chat_message_tb')
          .select('id,message')
          .eq('conversation_id', conversationId)
          .eq('sender_id', userId)
          .or('message.like.%[ITEM_INQUIRY:%,message.like.ฉันสนใจ%')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        final inquiry = ItemInquiryData.fromChatMessage(
          row['message']?.toString() ?? '',
        );
        if (inquiry != null && inquiry.itemId == itemId) {
          return (messageId: row['id'].toString(), inquiry: inquiry);
        }
      }
      if (rows.length < pageSize) return null;
    }
  }

  Future<void> sendMessage({
    required String conversationId,
    required String message,
    String? imageUrl,
  }) async {
    final client = _supabaseClient;
    final currentUserId = _currentUserId;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final offer = BookingRequestData.fromChatMessage(message);

    try {
      // การเปิดข้อความสอบถามเดิมอาจล้างคำขอหมดเวลาโดยไม่เพิ่มข้อความใหม่
      await client.schema('messaging').from('chat_message_tb').insert({
        'conversation_id': conversationId,
        'sender_id': currentUserId,
        'message': message.trim(),
        'image_url': imageUrl,
        // ข้อเสนอในคิวต้องเปรียบเทียบอายุกับเวลายืนยันสิทธิ์ฝั่งเซิร์ฟเวอร์
        if (offer?.rentalQueueMessageId == null) 'created_at': nowIso,
      }, defaultToNull: false);

      // ฐานข้อมูลอัปเดตข้อความล่าสุดพร้อม auto reply ใน transaction เดียว

      // Trigger สร้างประวัติและคิว Push ใน transaction ที่บันทึกข้อความแล้ว
    } on PostgrestException catch (e) {
      throw ChatRemoteException('ส่งข้อความไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการส่งข้อความ');
    }
  }

  String? _extractStoragePath(String imageUrl) {
    if (imageUrl.isEmpty) return null;
    final trimmed = imageUrl.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final pathSegments = uri.pathSegments;
    final bucketIndex = pathSegments.indexOf(_chatBucket);
    if (bucketIndex != -1 && bucketIndex + 1 < pathSegments.length) {
      final subPath = pathSegments.sublist(bucketIndex + 1).join('/');
      return Uri.decodeComponent(subPath);
    }
    return null;
  }

  Future<void> deleteMessage({
    required String messageId,
    required String conversationId,
    String? imageUrl,
  }) async {
    if (messageId.startsWith('temp_') || int.tryParse(messageId) == null) {
      return;
    }

    final client = _supabaseClient;
    try {
      final parsedId = int.parse(messageId);

      // ถ้าไม่ได้ส่ง imageUrl มา ให้ query ค้นหา URL รูปภาพก่อนลบจากฐานข้อมูล
      String? targetImageUrl = imageUrl;
      if (targetImageUrl == null || targetImageUrl.isEmpty) {
        try {
          final res = await client
              .schema('messaging')
              .from('chat_message_tb')
              .select('image_url')
              .eq('id', parsedId)
              .maybeSingle();
          targetImageUrl = res?['image_url'] as String?;
        } catch (_) {}
      }

      // ลบรูปภาพจาก Supabase Storage (ถ้ามี)
      if (targetImageUrl != null && targetImageUrl.isNotEmpty) {
        final storagePath = _extractStoragePath(targetImageUrl);
        if (storagePath != null && storagePath.isNotEmpty) {
          try {
            await client.storage.from(_chatBucket).remove([storagePath]);
          } catch (e) {
            debugPrint('Failed to delete message image from storage: $e');
          }
        }
      }

      // ลบข้อความออกจากฐานข้อมูล Supabase
      await client
          .schema('messaging')
          .from('chat_message_tb')
          .delete()
          .eq('id', parsedId);

      // อัปเดตข้อความล่าสุด (last_message) ใน conversation_tb ให้เป็นข้อความล่าสุดที่เหลืออยู่
      try {
        final latestMsg = await client
            .schema('messaging')
            .from('chat_message_tb')
            .select('message, image_url, created_at')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (latestMsg != null) {
          final lastText = latestMsg['message']?.toString().trim() ?? '';
          final lastImg = latestMsg['image_url']?.toString();
          final displayLastMsg =
              lastImg != null &&
                  lastImg.isNotEmpty &&
                  (lastText.isEmpty || lastText == '📷 ส่งรูปภาพ')
              ? '[รูปภาพ]'
              : lastText;
          final lastAt =
              latestMsg['created_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String();

          await client
              .schema('messaging')
              .from('conversation_tb')
              .update({
                'last_message': displayLastMsg,
                'last_message_at': lastAt,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', conversationId);
        } else {
          await client
              .schema('messaging')
              .from('conversation_tb')
              .update({
                'last_message': '',
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', conversationId);
        }
      } catch (e) {
        debugPrint(
          'Failed to update conversation last_message after delete: $e',
        );
      }
    } on PostgrestException catch (e) {
      throw ChatRemoteException('ลบข้อความไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการลบข้อความ');
    }
  }

  Future<void> editRentalQueueOffer({
    required String messageId,
    required String conversationId,
    required String originalMessage,
    required String newMessage,
  }) async {
    final id = int.tryParse(messageId);
    if (id == null || id <= 0) {
      throw const ChatRemoteException('ไม่พบการ์ดข้อเสนอที่ต้องการแก้ไข');
    }

    final List<Map<String, dynamic>> updated;
    try {
      updated = await _supabaseClient
          .schema('messaging')
          .from('chat_message_tb')
          .update({'message': newMessage})
          .eq('id', id)
          .eq('conversation_id', conversationId)
          .eq('message', originalMessage)
          .select('id');
    } on PostgrestException {
      throw const ChatRemoteException('แก้ไขข้อเสนอไม่สำเร็จ กรุณาลองใหม่');
    }
    // ถ้าข้อเสนอเปลี่ยนไปแล้ว ให้กลับไปเปิดการ์ดล่าสุดก่อนแก้ไขอีกครั้ง
    if (updated.isEmpty) {
      throw const ChatRemoteException(
        'บันทึกการแก้ไขไม่ได้ กรุณากลับไปเปิดการ์ดข้อเสนออีกครั้ง',
      );
    }
  }

  Future<void> editMessage({
    required String messageId,
    required String newMessage,
    String? conversationId,
  }) async {
    if (messageId.startsWith('temp_') || int.tryParse(messageId) == null) {
      return;
    }
    final client = _supabaseClient;
    try {
      final dynamic parsedId = int.tryParse(messageId) ?? messageId;
      await client
          .schema('messaging')
          .from('chat_message_tb')
          .update({'message': newMessage})
          .eq('id', parsedId);

      if (conversationId != null && conversationId.isNotEmpty) {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        try {
          await client
              .schema('messaging')
              .from('conversation_tb')
              .update({
                'last_message': newMessage.trim(),
                'last_message_at': nowIso,
                'updated_at': nowIso,
              })
              .eq('id', conversationId);
        } catch (_) {}
      }
    } on PostgrestException catch (e) {
      throw ChatRemoteException('แก้ไขข้อความไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการแก้ไขข้อความ');
    }
  }

  Future<void> deleteConversation({required String conversationId}) async {
    final client = _supabaseClient;
    try {
      // 1. ค้นหาและลบรูปภาพทั้งหมดที่แนบในการสนทนานี้ออกจาก Supabase Storage
      try {
        final records = await client
            .schema('messaging')
            .from('chat_message_tb')
            .select('image_url')
            .eq('conversation_id', conversationId)
            .not('image_url', 'is', null);

        final imagePaths = <String>[];
        for (final row in records) {
          final url = row['image_url'] as String?;
          if (url != null && url.isNotEmpty) {
            final path = _extractStoragePath(url);
            if (path != null && path.isNotEmpty) {
              imagePaths.add(path);
            }
          }
        }

        if (imagePaths.isNotEmpty) {
          try {
            await client.storage.from(_chatBucket).remove(imagePaths);
          } catch (e) {
            debugPrint('Failed to delete conversation images from storage: $e');
          }
        }
      } catch (e) {
        debugPrint(
          'Failed to fetch/delete chat images during conversation deletion: $e',
        );
      }

      // 2. ลบข้อความทั้งหมดของการสนทนานี้ในตาราง chat_message_tb
      await client
          .schema('messaging')
          .from('chat_message_tb')
          .delete()
          .eq('conversation_id', conversationId);

      // 3. ลบห้องสนทนาในตาราง conversation_tb
      await client
          .schema('messaging')
          .from('conversation_tb')
          .delete()
          .eq('id', conversationId);
    } on PostgrestException catch (e) {
      throw ChatRemoteException('ลบการสนทนาไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการลบการสนทนา');
    }
  }

  Stream<List<IncomingChatMessageData>> streamIncomingMessages() {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const Stream.empty();
    }

    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    return client
        .schema('messaging')
        .from('conversation_tb')
        .stream(primaryKey: ['id'])
        .asyncMap((records) async {
          final now = DateTime.now().toUtc();
          final results = <IncomingChatMessageData>[];

          for (final conv in records) {
            final renterId = conv['renter_id']?.toString() ?? '';
            final ownerId = conv['owner_id']?.toString() ?? '';

            if (renterId.isEmpty ||
                ownerId.isEmpty ||
                (renterId != currentUserId && ownerId != currentUserId)) {
              continue;
            }

            final lastMsgAtStr = conv['last_message_at']?.toString();
            if (lastMsgAtStr == null || lastMsgAtStr.isEmpty) continue;

            try {
              final lastMsgAt = DateTime.parse(lastMsgAtStr).toUtc();
              // ตรวจสอบว่าเป็นข้อความใหม่ภายใน 20 วินาทีล่าสุด
              if (now.difference(lastMsgAt).inSeconds.abs() > 20) {
                continue;
              }
            } catch (_) {
              continue;
            }

            final convId = conv['id']?.toString() ?? '';
            if (convId.isEmpty) continue;

            // ดึงข้อความล่าสุดในห้องนี้
            try {
              final latestMsgRow = await client
                  .schema('messaging')
                  .from('chat_message_tb')
                  .select('*')
                  .eq('conversation_id', convId)
                  .order('created_at', ascending: false)
                  .limit(1)
                  .maybeSingle();

              if (latestMsgRow == null) continue;

              final senderId = latestMsgRow['sender_id']?.toString() ?? '';
              if (senderId == currentUserId)
                continue; // ข้อความที่ส่งโดยตัวเอง ไม่ต้องแจ้งเตือน

              final otherId = currentUserId == renterId ? ownerId : renterId;

              final profile = await client
                  .schema('profiles')
                  .from('public_profile_v')
                  .select(
                    'user_id,user_image_url,is_online,last_seen_at,display_name',
                  )
                  .eq('user_id', otherId)
                  .maybeSingle();
              if (profile == null) continue;

              Map<String, dynamic>? item;
              if (conv['item_id'] != null) {
                item = await client
                    .from('item_tb')
                    .select(_conversationItemColumns)
                    .eq('id', conv['item_id'])
                    .maybeSingle();
              }

              final chatConv = ChatConversationModel.fromRecords(
                conversation: conv,
                otherProfile: profile,
                item: item,
                currentUserId: currentUserId,
                hasUnreadMessage: true,
              );

              final createdAt =
                  DateTime.tryParse(
                    latestMsgRow['created_at']?.toString() ?? '',
                  ) ??
                  DateTime.now();

              results.add(
                IncomingChatMessageData(
                  id: latestMsgRow['id']?.toString() ?? '',
                  conversationId: convId,
                  senderId: senderId,
                  message: latestMsgRow['message']?.toString() ?? '',
                  imageUrl: latestMsgRow['image_url']?.toString(),
                  createdAt: createdAt,
                  conversation: chatConv,
                ),
              );
            } catch (_) {}
          }

          return results;
        })
        .handleError((error) {
          debugPrint('streamLatestIncomingMessage connection error: $error');
        });
  }

  static String _extension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return 'jpg';
    final value = fileName.substring(index + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(value) ? value : 'jpg';
  }

  static String _contentType(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

class IncomingChatMessageData {
  const IncomingChatMessageData({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.message,
    required this.imageUrl,
    required this.createdAt,
    required this.conversation,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String message;
  final String? imageUrl;
  final DateTime createdAt;
  final ChatConversation conversation;
}
