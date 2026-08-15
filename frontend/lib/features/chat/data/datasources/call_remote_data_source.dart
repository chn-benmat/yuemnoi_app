import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/chat_conversation.dart';
import '../models/chat_conversation_model.dart';
import 'chat_remote_data_source.dart';

class CallSessionData {
  const CallSessionData({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.receiverId,
    required this.status,
    this.callerConversation,
  });

  final String id;
  final String conversationId;
  final String callerId;
  final String receiverId;
  final String status;
  final ChatConversation? callerConversation;

  factory CallSessionData.fromJson(Map<String, dynamic> json, {ChatConversation? callerConversation}) {
    return CallSessionData(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      callerId: json['caller_id']?.toString() ?? '',
      receiverId: json['receiver_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'ringing',
      callerConversation: callerConversation,
    );
  }
}

class CallRemoteDataSource {
  CallRemoteDataSource({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

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
      throw const ChatRemoteException('กรุณาเข้าสู่ระบบก่อนใช้งาน');
    }
    return userId;
  }

  Future<String> createCallSession({
    required String conversationId,
    required String receiverId,
  }) async {
    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    try {
      final res = await client
          .from('call_session_tb')
          .insert({
            'conversation_id': conversationId,
            'caller_id': currentUserId,
            'receiver_id': receiverId,
            'status': 'ringing',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();

      return res['id']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> updateCallStatus({
    required String sessionId,
    required String status,
  }) async {
    if (sessionId.isEmpty) return;
    final client = _supabaseClient;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final updateData = <String, dynamic>{'status': status};
    if (status == 'accepted') {
      updateData['started_at'] = nowIso;
    } else if (status == 'ended' || status == 'rejected') {
      updateData['ended_at'] = nowIso;
    }

    try {
      await client
          .from('call_session_tb')
          .update(updateData)
          .eq('id', sessionId);
    } catch (_) {}
  }

  Stream<String> streamCallStatus(String sessionId) {
    if (!SupabaseConfig.isInitialized && _client == null || sessionId.isEmpty) {
      return const Stream.empty();
    }

    final client = _supabaseClient;
    return client
        .from('call_session_tb')
        .stream(primaryKey: ['id'])
        .eq('id', sessionId)
        .map((records) {
          if (records.isEmpty) return 'ended';
          return records.first['status']?.toString() ?? 'ended';
        });
  }

  Stream<CallSessionData> streamIncomingCalls() {
    if (!SupabaseConfig.isInitialized && _client == null) {
      return const Stream.empty();
    }

    final client = _supabaseClient;
    final currentUserId = _currentUserId;

    return client
        .from('call_session_tb')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', currentUserId)
        .asyncMap((records) async {
          final ringingList = records
              .where((r) => r['status'] == 'ringing')
              .toList(growable: false);

          if (ringingList.isEmpty) {
            return const CallSessionData(
              id: '',
              conversationId: '',
              callerId: '',
              receiverId: '',
              status: 'idle',
            );
          }

          final latest = ringingList.last;
          final callerId = latest['caller_id']?.toString() ?? '';
          final convId = latest['conversation_id']?.toString() ?? '';

          // ดึงข้อมูลโปรไฟล์ผู้โทรและอุปกรณ์
          ChatConversation? callerConv;
          try {
            final conv = await client
                .from('conversation_tb')
                .select('*')
                .eq('id', convId)
                .maybeSingle();

            final profile = await client
                .from('profile_tb')
                .select('user_id,user_image_url,email,is_online,last_seen_at')
                .eq('user_id', callerId)
                .maybeSingle();

            Map<String, dynamic>? item;
            if (conv != null && conv['item_id'] != null) {
              item = await client
                  .from('item_tb')
                  .select('id,item_name,item_image_url,price,type')
                  .eq('id', conv['item_id'])
                  .maybeSingle();
            }

            if (conv != null) {
              callerConv = ChatConversationModel.fromRecords(
                conversation: conv,
                otherProfile: profile,
                item: item,
                currentUserId: currentUserId,
              );
            }
          } catch (_) {}

          return CallSessionData.fromJson(latest, callerConversation: callerConv);
        });
  }
}
