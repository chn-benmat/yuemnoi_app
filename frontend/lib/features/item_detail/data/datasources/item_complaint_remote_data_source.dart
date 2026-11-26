import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';

class ItemComplaintRemoteDataSource {
  const ItemComplaintRemoteDataSource({ApiClient? apiClient})
    : _apiClient = apiClient;

  final ApiClient? _apiClient;

  Future<void> submit({
    required int itemId,
    required String description,
  }) async {
    final token = AuthSession.accessToken;
    if (token == null) {
      throw const ItemComplaintException(
        'กรุณาเข้าสู่ระบบอีกครั้งเพื่อส่งรายงาน',
      );
    }

    final api = _apiClient ?? DioApiClient();
    try {
      final response = await api.post(
        '/api/complaints',
        headers: {'Authorization': 'Bearer $token'},
        data: {'item_id': itemId, 'description': description},
      );
      final data = response.data;
      final reportId = data is Map ? data['id'] : null;
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          reportId is String &&
          reportId.isNotEmpty) {
        return;
      }
      final message = data is Map ? data['error'] : null;
      throw ItemComplaintException(
        message is String ? message : 'ส่งรายงานไม่สำเร็จ กรุณาลองใหม่',
      );
    } on ApiClientException {
      throw const ItemComplaintException('เชื่อมต่อระบบไม่ได้ กรุณาลองใหม่');
    } finally {
      if (_apiClient == null) api.close();
    }
  }
}

class ItemComplaintException implements Exception {
  const ItemComplaintException(this.message);

  final String message;
}
