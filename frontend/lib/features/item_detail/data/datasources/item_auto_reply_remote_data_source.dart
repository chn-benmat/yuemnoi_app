import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/item_auto_reply.dart';

class ItemAutoReplyRemoteDataSource {
  ItemAutoReplyRemoteDataSource({ApiClient? apiClient})
    : _api = apiClient ?? DioApiClient();
  final ApiClient _api;

  Future<ItemAutoReply> load(int itemId) => _request(itemId);
  Future<ItemAutoReply> save(int itemId, ItemAutoReply settings) =>
      _request(itemId, settings: settings);

  Future<ItemAutoReply> _request(int itemId, {ItemAutoReply? settings}) async {
    final token = AuthSession.accessToken;
    if (token == null)
      throw const ItemAutoReplyException(
        'กรุณาเข้าสู่ระบบเพื่อตั้งค่าการตอบกลับ',
      );
    try {
      final headers = {'Authorization': 'Bearer $token'};
      final path = '/api/items/$itemId/auto-reply';
      final response = settings == null
          ? await _api.get(path, headers: headers)
          : await _api.put(
              path,
              headers: headers,
              data: {'enabled': settings.enabled, 'message': settings.message},
            );
      final data = response.data;
      if (response.statusCode != 200 ||
          data is! Map ||
          data['enabled'] is! bool ||
          data['message'] is! String) {
        final message = data is Map ? data['error']?.toString() : null;
        throw ItemAutoReplyException(
          message ?? 'โหลดหรือบันทึกการตอบกลับไม่สำเร็จ กรุณาลองใหม่',
        );
      }
      return ItemAutoReply(
        enabled: data['enabled'] as bool,
        message: data['message'] as String,
      );
    } on ItemAutoReplyException {
      rethrow;
    } catch (_) {
      throw const ItemAutoReplyException('เชื่อมต่อระบบไม่สำเร็จ กรุณาลองใหม่');
    }
  }
}
