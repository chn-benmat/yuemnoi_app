import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/favorite_service.dart';
import '../models/favorite_item_model.dart';
import '../models/user_item_model.dart';

// คำอธิบาย: ดึงอุปกรณ์ของผู้ใช้และรายการโปรด โดยรับชื่อเจ้าของผ่าน API
class UserItemsRemoteDataSource {
  UserItemsRemoteDataSource({
    SupabaseClient? client,
    ApiClient? apiClient,
    Future<List<int>> Function()? getFavoriteIds,
  }) : _client = client,
       _apiClient = apiClient,
       _getFavoriteIds =
           getFavoriteIds ?? FavoriteService.instance.getFavoriteIds;

  ApiClient? _apiClient;
  final Future<List<int>> Function() _getFavoriteIds;
  ApiClient get _backendClient => _apiClient ??= DioApiClient();

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
    final favIds = await _getFavoriteIds();
    final items = <FavoriteItemModel>[];
    for (var offset = 0; offset < favIds.length; offset += 6) {
      final batch = favIds.skip(offset).take(6);
      final results = await Future.wait(
        batch.map((id) async {
          final response = await _backendClient.get('/api/items/$id');
          if (response.statusCode == 404) return null;
          if (response.statusCode != 200 || response.data is! Map) {
            throw const ApiClientException(ApiClientErrorType.invalidResponse);
          }
          return FavoriteItemModel.fromJson(
            Map<String, dynamic>.from(response.data as Map),
          );
        }),
      );
      items.addAll(results.whereType<FavoriteItemModel>());
    }
    return items;
  }
}
