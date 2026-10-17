import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
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
            .from('conversation_tb')
            .insert(insertData)
            .select('*')
            .single();
      }

      // 3. ดึงข้อมูลโปรไฟล์ของคู่สนทนา (เจ้าของอุปกรณ์ / ผู้ใช้ที่สนทนาด้วย) ผ่าน secure view
      final otherProfile = await client
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
              .select('id,item_name,item_image_url,price,type')
              .eq('id', parsedId)
              .maybeSingle();
        }
      }

      return ChatConversationModel.fromRecords(
        conversation: conversation,
        otherProfile: otherProfile,
        item: item,
        currentUserId: currentUserId,
      );
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
              .select('id,item_name,item_image_url,price,type')
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

  Future<List<ChatConversation>> getConversations() async {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const [];
    }

    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    try {
      final rawConversations = await client
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
        if (otherId.isEmpty) continue;
        if (!seenOtherUserIds.contains(otherId)) {
          seenOtherUserIds.add(otherId);
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

      // ดึงโปรไฟล์ทั้งหมด (พร้อม try-catch ป้องกัน sub-query error)
      final profilesMap = <String, Map<String, dynamic>>{};
      if (otherUserIds.isNotEmpty) {
        try {
          final profiles = await client
              .from('public_profile_v')
              .select(
                'user_id,user_image_url,is_online,last_seen_at,display_name',
              )
              .inFilter('user_id', otherUserIds.toList(growable: false));
          for (final p in (profiles as List).cast<Map<String, dynamic>>()) {
            final uid = p['user_id']?.toString();
            if (uid != null) profilesMap[uid] = p;
          }
        } catch (e) {
          debugPrint('getConversations profiles sub-query error: $e');
        }
      }

      // ดึงข้อมูล item ทั้งหมด (พร้อม try-catch ป้องกัน sub-query error)
      final itemsMap = <int, Map<String, dynamic>>{};
      if (itemIds.isNotEmpty) {
        try {
          final items = await client
              .from('item_tb')
              .select('id,item_name,item_image_url,price,type')
              .inFilter('id', itemIds.toList(growable: false));
          for (final item in (items as List).cast<Map<String, dynamic>>()) {
            final id = item['id'] is num
                ? (item['id'] as num).toInt()
                : int.tryParse(item['id'].toString());
            if (id != null) itemsMap[id] = item;
          }
        } catch (e) {
          debugPrint('getConversations items sub-query error: $e');
        }
      }

      // ดึงรายชื่อ conversation_id ที่มีข้อความที่ยังไม่ได้อ่าน
      Set<String> unreadConvIds = {};
      try {
        final unreadRows = await client
            .from('chat_message_tb')
            .select('conversation_id')
            .neq('sender_id', currentUserId)
            .eq('is_read', false);
        unreadConvIds = (unreadRows as List)
            .map((r) => r['conversation_id']?.toString())
            .whereType<String>()
            .toSet();
      } catch (_) {}

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
          .from('chat_message_tb')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', currentUserId);
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
          .from('chat_message_tb')
          .select('*')
          .eq('conversation_id', conversationId);

      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }

      final records = await query
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (records as List)
          .cast<Map<String, dynamic>>()
          .map(
            (json) =>
                ChatMessageModel.fromJson(json, currentUserId: currentUserId),
          )
          .toList(growable: false);

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

    return client
        .from('chat_message_tb')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map(
          (records) => records
              .map(
                (json) => ChatMessageModel.fromJson(
                  json,
                  currentUserId: currentUserId,
                ),
              )
              .toList(),
        )
        .handleError((error) {
          debugPrint('streamMessages connection error: $error');
        });
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

  Future<void> sendMessage({
    required String conversationId,
    required String message,
    String? imageUrl,
  }) async {
    final client = _supabaseClient;
    final currentUserId = _currentUserId;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    try {
      final displayLastMsg = imageUrl != null && message.trim().isEmpty
          ? '[รูปภาพ]'
          : message.trim();

      final inserted = await client
          .from('chat_message_tb')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUserId,
            'message': message.trim(),
            'image_url': imageUrl,
            'created_at': nowIso,
          })
          .select('id')
          .maybeSingle();

      final newMsgId = inserted?['id']?.toString() ?? '';

      await client
          .from('conversation_tb')
          .update({
            'last_message': displayLastMsg,
            'last_message_at': nowIso,
            'updated_at': nowIso,
          })
          .eq('id', conversationId);

      // ส่ง Push Notification ไปยังผู้รับในระบบ OS (ทำงานแบบ Background Non-blocking)
      unawaited(
        sendChatPushNotification(
          conversationId: conversationId,
          message: displayLastMsg,
          messageId: newMsgId,
        ),
      );
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
      await client.from('chat_message_tb').delete().eq('id', parsedId);

      // อัปเดตข้อความล่าสุด (last_message) ใน conversation_tb ให้เป็นข้อความล่าสุดที่เหลืออยู่
      try {
        final latestMsg = await client
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
              .from('conversation_tb')
              .update({
                'last_message': displayLastMsg,
                'last_message_at': lastAt,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', conversationId);
        } else {
          await client
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
          .from('chat_message_tb')
          .update({'message': newMessage})
          .eq('id', parsedId);

      if (conversationId != null && conversationId.isNotEmpty) {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        try {
          await client
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
          .from('chat_message_tb')
          .delete()
          .eq('conversation_id', conversationId);

      // 3. ลบห้องสนทนาในตาราง conversation_tb
      await client.from('conversation_tb').delete().eq('id', conversationId);
    } on PostgrestException catch (e) {
      throw ChatRemoteException('ลบการสนทนาไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการลบการสนทนา');
    }
  }

  Future<void> sendChatPushNotification({
    required String conversationId,
    required String message,
    String? messageId,
  }) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) return;

    try {
      final client = _supabaseClient;
      final currentUserId = _currentUserId;

      final convRes = await client
          .from('conversation_tb')
          .select('renter_id, owner_id')
          .eq('id', conversationId)
          .maybeSingle();

      if (convRes == null) return;
      final renterId = convRes['renter_id']?.toString() ?? '';
      final ownerId = convRes['owner_id']?.toString() ?? '';
      final receiverId = currentUserId == renterId ? ownerId : renterId;

      if (receiverId.isEmpty) return;

      // สกัดเอาเฉพาะข้อความตอบกลับตัวจริง โดยตัดคำนำหน้า '↩ ตอบกลับ:...' ออก ไม่ให้ขึ้นคำว่าตอบกลับใน Push Notification
      final cleanMessageForPush = _extractCleanPushMessage(message);

      await _backendClient.post(
        '/api/push/chat',
        headers: {'Authorization': 'Bearer $token'},
        data: {
          'receiver_id': receiverId,
          'message': cleanMessageForPush,
          'message_id': messageId ?? '',
          'conversation_id': conversationId,
        },
      );
    } catch (e) {
      debugPrint('sendChatPushNotification error: $e');
    }
  }

  Stream<List<IncomingChatMessageData>> streamIncomingMessages() {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const Stream.empty();
    }

    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    return client
        .from('conversation_tb')
        .stream(primaryKey: ['id'])
        .asyncMap((records) async {
          final now = DateTime.now().toUtc();
          final results = <IncomingChatMessageData>[];

          for (final conv in records) {
            final renterId = conv['renter_id']?.toString() ?? '';
            final ownerId = conv['owner_id']?.toString() ?? '';

            if (renterId != currentUserId && ownerId != currentUserId) {
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
                  .from('public_profile_v')
                  .select(
                    'user_id,user_image_url,is_online,last_seen_at,display_name',
                  )
                  .eq('user_id', otherId)
                  .maybeSingle();

              Map<String, dynamic>? item;
              if (conv['item_id'] != null) {
                item = await client
                    .from('item_tb')
                    .select('id,item_name,item_image_url,price,type')
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

  static String _extractCleanPushMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '📷 ส่งรูปภาพ';
    if (trimmed.startsWith('↩ ตอบกลับ:') ||
        trimmed.startsWith('💬 ตอบกลับ') ||
        trimmed.startsWith('↪ ตอบกลับ')) {
      final newlineIdx = trimmed.indexOf('\n');
      if (newlineIdx != -1) {
        final actual = trimmed.substring(newlineIdx + 1).trim();
        return actual.isNotEmpty ? actual : 'ส่งข้อความถึงคุณ';
      }
      final pipeParts = trimmed.split('|');
      if (pipeParts.length >= 2) {
        final actual = pipeParts[1].trim();
        return actual.isNotEmpty ? actual : 'ส่งข้อความถึงคุณ';
      }
    }
    return trimmed;
  }
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
