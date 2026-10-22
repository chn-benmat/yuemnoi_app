import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../../chat/data/datasources/chat_remote_data_source.dart';

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
          .limit(1);
      conversationId = conversations.isEmpty
          ? null
          : conversations.first['id'] as String;
    }
    if (conversationId == null || conversationId.trim().isEmpty) {
      throw const ChatRemoteException('ไม่พบข้อมูลติดต่อของรายการเช่านี้');
    }
    return _chat.getConversationContactPhone(conversationId);
  }
}
