import '../../../../core/network/api_client.dart';
import '../../domain/repositories/related_items_repository.dart';

class RelatedItemsRemoteDataSource {
  RelatedItemsRemoteDataSource({ApiClient? apiClient})
    : _api = apiClient ?? DioApiClient();
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> fetchByCategory(String category) async {
    try {
      final response = await _api.get(
        '/api/items',
        queryParameters: {'category': category},
      );
      if (response.statusCode != 200) {
        throw const RelatedItemsException('โหลดสินค้าใกล้เคียงไม่สำเร็จ');
      }
      if (response.data == null) return const [];
      if (response.data is! List) {
        throw const RelatedItemsException('ข้อมูลสินค้าใกล้เคียงไม่ถูกต้อง');
      }
      return (response.data as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } on RelatedItemsException {
      rethrow;
    } catch (_) {
      throw const RelatedItemsException('โหลดสินค้าใกล้เคียงไม่สำเร็จ');
    }
  }
}
