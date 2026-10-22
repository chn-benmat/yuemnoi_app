import '../../../../core/network/api_client.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/favorite_service.dart';
import '../models/favorite_item_model.dart';
import '../models/user_item_model.dart';

// คำอธิบาย: ดึงอุปกรณ์ของผู้ใช้และรายการโปรด โดยรับชื่อเจ้าของผ่าน API
class UserItemsRemoteDataSource {
  UserItemsRemoteDataSource({
    ApiClient? apiClient,
    Future<List<int>> Function()? getFavoriteIds,
  }) : _apiClient = apiClient,
       _getFavoriteIds =
           getFavoriteIds ?? FavoriteService.instance.getFavoriteIds;

  ApiClient? _apiClient;
  final Future<List<int>> Function() _getFavoriteIds;
  ApiClient get _backendClient => _apiClient ??= DioApiClient();

  Future<List<UserItemModel>> getMyItems(String userId) async {
    if (!SupabaseConfig.isInitialized || userId.isEmpty) {
      return [];
    }

    try {
      final response = await SupabaseConfig.client
          .from('item_tb')
          .select(
            'id, user_id, item_name, item_image_url, description, category, price, status',
          )
          .eq('user_id', userId)
          .order('id', ascending: false);

      final List<UserItemModel> items = [];
      for (final raw in (response as List)) {
        if (raw is Map) {
          items.add(UserItemModel.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      return items;
    } catch (_) {
      return [];
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
