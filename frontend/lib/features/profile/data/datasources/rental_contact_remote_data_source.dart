import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';
import '../../../chat/domain/entities/chat_conversation.dart';

class RentalContactRemoteDataSource {
  RentalContactRemoteDataSource({
    SupabaseClient? client,
    ChatRemoteDataSource? chat,
  }) : _client = client,
       _chat = chat ?? ChatRemoteDataSource();

  final SupabaseClient? _client;
  final ChatRemoteDataSource _chat;

  Future<String> getPhone({int? bookingId, String? conversationId}) async {
    if (bookingId != null) {
      conversationId = await _findConversationId(bookingId);
    }
    if (conversationId == null || conversationId.trim().isEmpty) {
      throw const ChatRemoteException('ไม่พบข้อมูลติดต่อของรายการเช่านี้');
    }
    return _chat.getConversationContactPhone(conversationId);
  }

  Future<ChatConversation?> getConversation({
    int? bookingId,
    String? conversationId,
  }) async {
    var id = conversationId?.trim();
    if ((id == null || id.isEmpty) && bookingId != null) {
      id = await _findConversationId(bookingId);
    }
    if (id == null || id.isEmpty) return null;
    return _chat.getConversationById(id);
  }

  Future<String?> _findConversationId(int bookingId) async {
    final client = _client ?? SupabaseConfig.client;
    final booking = await client
        .from('booking_tb')
        .select('user_id,item_id')
        .eq('id', bookingId)
        .single();
    final item = await client
        .from('item_tb')
        .select('user_id')
        .eq('id', booking['item_id'])
        .single();
    final renter = booking['user_id'] as String;
    final owner = item['user_id'] as String;
    // ห้องแชทใช้ร่วมกันได้ทั้งสองทิศทาง จึงค้นหาจากคู่สัญญาของการจอง
    final conversations = await client
        .schema('messaging')
        .from('conversation_tb')
        .select('id')
        .or(
          'and(renter_id.eq.$renter,owner_id.eq.$owner),and(renter_id.eq.$owner,owner_id.eq.$renter)',
        )
        .order('last_message_at', ascending: false)
        .limit(1);
    return conversations.isEmpty ? null : conversations.first['id'] as String;
  }
}
