import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/app_notification.dart';

class NotificationRemoteDataSource {
  NotificationRemoteDataSource({ApiClient? client, String? Function()? token})
    : _client = client ?? DioApiClient(),
      _token = token ?? (() => AuthSession.accessToken);

  final ApiClient _client;
  final String? Function() _token;

  Map<String, String> get _headers {
    final token = _token();
    if (token == null || token.isEmpty) {
      throw const NotificationFailure('กรุณาเข้าสู่ระบบเพื่อดูการแจ้งเตือน');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> fetch({int limit = 50, int offset = 0}) async {
    final response = await _client.get(
      '/api/notifications',
      headers: _headers,
      queryParameters: {'limit': limit, 'offset': offset},
    );
    _check(response);
    if (response.data is! Map) {
      throw const NotificationFailure('รูปแบบข้อมูลแจ้งเตือนไม่ถูกต้อง');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> post(String path, {Map<String, dynamic>? data}) async =>
      _check(await _client.post(path, headers: _headers, data: data));

  void _check(ApiResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const NotificationFailure(
        'โหลดหรือบันทึกการแจ้งเตือนไม่สำเร็จ กรุณาลองใหม่',
      );
    }
  }

  void close() => _client.close();
}
