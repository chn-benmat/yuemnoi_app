import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/favorite_service.dart';
import '../models/favorite_item_model.dart';
import '../models/user_item_model.dart';

// คำอธิบาย: Data Source สำหรับดึงข้อมูลอุปกรณ์ของผู้ใช้และรายการที่กดถูกใจจาก Supabase
class UserItemsRemoteDataSource {
  UserItemsRemoteDataSource({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  static const _pageSize = 500;

  Future<List<UserItemModel>> getMyItems(String userId) async {
    if (userId.isEmpty) throw ArgumentError.value(userId, 'userId');
    final client = _client ?? SupabaseConfig.client;

    final items = <UserItemModel>[];
    // อ่านให้ครบทุกหน้า เพื่อให้ยอดในตัวกรองตรงกับอุปกรณ์ของเจ้าของทั้งหมด
    for (var offset = 0; ; offset += _pageSize) {
      final response = await client
          .from('item_tb')
          .select(
            'id, user_id, item_name, item_image_url, description, category, price, status, type, owner_hidden',
          )
          .eq('user_id', userId)
          .order('id', ascending: false)
          .range(offset, offset + _pageSize - 1);

      for (final raw in response) {
        items.add(UserItemModel.fromJson(raw));
      }
      if (response.length < _pageSize) return items;
    }
  }

  Future<List<FavoriteItemModel>> getFavorites() async {
    final favIds = await FavoriteService.instance.getFavoriteIds();
    if (favIds.isEmpty || !SupabaseConfig.isInitialized) {
      return [];
    }

    try {
      final client = SupabaseConfig.client;
      final response = await client
          .from('item_tb')
          .select(
            'id, user_id, item_name, item_image_url, description, category, price, status',
          )
          .inFilter('id', favIds)
          .eq('owner_hidden', false)
          .eq('moderation_hidden', false);

      final Set<String> ownerIds = {};
      final List<Map<String, dynamic>> rawList = [];

      for (final raw in (response as List)) {
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          rawList.add(map);
          final ownerId = map['user_id']?.toString() ?? '';
          if (ownerId.isNotEmpty) ownerIds.add(ownerId);
        }
      }

      final Map<String, String> ownerNames = {};
      if (ownerIds.isNotEmpty) {
        try {
          final profiles = await client
              .schema('profiles')
              .from('public_profile_v')
              .select('user_id, display_name, email')
              .inFilter('user_id', ownerIds.toList());

          for (final p in (profiles as List)) {
            if (p is Map) {
              final uid = p['user_id']?.toString();
              final displayName = p['display_name']?.toString().trim() ?? '';
              final email = p['email']?.toString() ?? '';
              if (uid != null) {
                ownerNames[uid] = displayName.isNotEmpty
                    ? displayName
                    : (email.isNotEmpty
                          ? email.split('@').first
                          : 'เจ้าของอุปกรณ์');
              }
            }
          }
        } catch (_) {}
      }

      final List<FavoriteItemModel> items = [];
      for (final map in rawList) {
        final ownerId = map['user_id']?.toString() ?? '';
        final ownerName = ownerNames[ownerId] ?? 'เจ้าของอุปกรณ์';
        items.add(FavoriteItemModel.fromJson(map, ownerName: ownerName));
      }

      return items;
    } catch (_) {
      return [];
    }
  }
}
