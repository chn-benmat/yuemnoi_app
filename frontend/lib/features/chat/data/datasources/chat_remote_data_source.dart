import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

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
  ChatRemoteDataSource({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  static const _chatBucket = 'chat_bk';

  SupabaseClient get _supabaseClient {
    if (_client != null) return _client!;
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
    required int itemId,
    required String ownerId,
  }) async {
    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    if (currentUserId == ownerId) {
      throw const ChatRemoteException('ไม่สามารถส่งข้อความหาตนเองได้');
    }

    try {
      // 1. ตรวจสอบว่าเคยมีห้องแชทสำหรับคู่นี้และอุปกรณ์นี้หรือไม่
      var conversation = await client
          .from('conversation_tb')
          .select('*')
          .eq('item_id', itemId)
          .eq('renter_id', currentUserId)
          .eq('owner_id', ownerId)
          .maybeSingle();

      // 2. ถ้ายังไม่มี ให้สร้างห้องใหม่
      if (conversation == null) {
        conversation = await client
            .from('conversation_tb')
            .insert({
              'item_id': itemId,
              'renter_id': currentUserId,
              'owner_id': ownerId,
              'last_message': '',
              'last_message_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select('*')
            .single();
      }

      // 3. ดึงข้อมูลโปรไฟล์ของคู่สนทนา (เจ้าของอุปกรณ์)
      final otherProfile = await client
          .from('profile_tb')
          .select('user_id,user_image_url,email,is_online,last_seen_at')
          .eq('user_id', ownerId)
          .maybeSingle();

      // 4. ดึงข้อมูลอุปกรณ์
      final item = await client
          .from('item_tb')
          .select('id,item_name,item_image_url,price,type')
          .eq('id', itemId)
          .maybeSingle();

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
      throw const ChatRemoteException('ไม่สามารถเชื่อมต่อห้องแชทได้ กรุณาลองใหม่');
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

      final conversations =
          (rawConversations as List).cast<Map<String, dynamic>>();
      if (conversations.isEmpty) return const [];

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

      // ดึงโปรไฟล์ทั้งหมด
      final profilesMap = <String, Map<String, dynamic>>{};
      if (otherUserIds.isNotEmpty) {
        final profiles = await client
            .from('profile_tb')
            .select('user_id,user_image_url,email,is_online,last_seen_at')
            .inFilter('user_id', otherUserIds.toList(growable: false));
        for (final p in (profiles as List).cast<Map<String, dynamic>>()) {
          final uid = p['user_id']?.toString();
          if (uid != null) profilesMap[uid] = p;
        }
      }

      // ดึงข้อมูล item ทั้งหมด
      final itemsMap = <int, Map<String, dynamic>>{};
      if (itemIds.isNotEmpty) {
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

      return conversations.map((conv) {
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
      }).toList(growable: false);
    } on ChatRemoteException {
      rethrow;
    } on PostgrestException catch (e) {
      throw ChatRemoteException('โหลดรายการแชทไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('ไม่สามารถดึงข้อมูลแชทได้ กรุณาลองใหม่');
    }
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
          .map((json) =>
              ChatMessageModel.fromJson(json, currentUserId: currentUserId))
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
        .map((records) => records
            .map((json) =>
                ChatMessageModel.fromJson(json, currentUserId: currentUserId))
            .toList());
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
        '$currentUserId/$conversationId/${DateTime.now().microsecondsSinceEpoch}.$extension';

    try {
      await client.storage.from(_chatBucket).uploadBinary(
            path,
            imageBytes,
            fileOptions: FileOptions(contentType: _contentType(extension)),
          );
      return client.storage.from(_chatBucket).getPublicUrl(path);
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
      await client.from('chat_message_tb').insert({
        'conversation_id': conversationId,
        'sender_id': currentUserId,
        'message': message.trim(),
        'image_url': imageUrl,
        'created_at': nowIso,
      });

      final displayLastMsg = imageUrl != null && message.trim().isEmpty
          ? '[รูปภาพ]'
          : message.trim();

      await client.from('conversation_tb').update({
        'last_message': displayLastMsg,
        'last_message_at': nowIso,
        'updated_at': nowIso,
      }).eq('id', conversationId);
    } on PostgrestException catch (e) {
      throw ChatRemoteException('ส่งข้อความไม่สำเร็จ: ${e.message}');
    } catch (_) {
      throw const ChatRemoteException('เกิดข้อผิดพลาดในการส่งข้อความ');
    }
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
