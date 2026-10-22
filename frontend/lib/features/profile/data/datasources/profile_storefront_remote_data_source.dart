import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';

class ProfileStorefrontRemoteDataSource {
  ProfileStorefrontRemoteDataSource({SupabaseClient? client})
    : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? SupabaseConfig.client;
  static const pageSize = 500;

  Future<Map<String, dynamic>> getIdentity(String userId) async {
    final profile = await client
        .schema('profiles')
        .from('public_profile_v')
        .select('display_name, user_image_url, is_verified')
        .eq('user_id', userId)
        .single();

    // คำแนะนำตัวอยู่ในข้อมูลส่วนตัว จึงอ่านเพิ่มได้เฉพาะเจ้าของที่ล็อกอิน
    if (client.auth.currentUser?.id == userId) {
      final ownProfile = await client
          .schema('profiles')
          .from('profile_tb')
          .select('bio')
          .eq('user_id', userId)
          .maybeSingle();
      profile['bio'] = ownProfile?['bio'];
    }
    return profile;
  }

  Future<List<Map<String, dynamic>>> getItems(String userId) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final rows = await client
          .from('item_tb')
          .select(
            'id, item_name, item_image_url, description, category, price, status, type',
          )
          .eq('user_id', userId)
          .eq('moderation_hidden', false)
          .eq('owner_hidden', false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      result.addAll(rows);
      if (rows.length < pageSize) return result;
    }
  }

  Future<List<Map<String, dynamic>>> getReviews(List<int> itemIds) async {
    final result = <Map<String, dynamic>>[];
    // จำกัดจำนวนรหัสต่อคำขอ เพื่อไม่ให้ URL ยาวเมื่อเจ้าของมีอุปกรณ์จำนวนมาก
    for (var start = 0; start < itemIds.length; start += 100) {
      final end = (start + 100).clamp(0, itemIds.length);
      final batch = itemIds.sublist(start, end);
      for (var offset = 0; ; offset += pageSize) {
        final rows = await client
            .from('review_tb')
            .select('id, item_id, rating, user_id, description, created_at')
            .inFilter('item_id', batch)
            .eq('moderation_hidden', false)
            .order('id', ascending: true)
            .range(offset, offset + pageSize - 1);
        result.addAll(rows);
        if (rows.length < pageSize) break;
      }
    }
    final userIds = result
        .map((row) => row['user_id'])
        .whereType<String>()
        .toSet()
        .toList();
    final profiles = <String, Map<String, dynamic>>{};
    for (var start = 0; start < userIds.length; start += 100) {
      final end = (start + 100).clamp(0, userIds.length);
      final rows = await client
          .schema('profiles')
          .from('public_profile_v')
          .select('user_id, display_name, user_image_url')
          .inFilter('user_id', userIds.sublist(start, end));
      for (final row in rows) {
        profiles[row['user_id'].toString()] = row;
      }
    }
    for (final row in result) {
      row['reviewer'] = profiles[row['user_id']];
    }
    return result;
  }
}
