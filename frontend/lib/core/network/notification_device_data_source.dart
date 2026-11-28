import 'api_client.dart';

class NotificationDeviceException implements Exception {
  const NotificationDeviceException(this.statusCode);
  final int statusCode;
}

class NotificationDeviceDataSource {
  NotificationDeviceDataSource({ApiClient? client})
    : _client =
          client ?? DioApiClient(requestTimeout: const Duration(seconds: 5));
  final ApiClient _client;

  Future<void> register({
    required String accessToken,
    required String installationId,
    required String token,
    required String platform,
  }) async {
    final response = await _client.put(
      '/api/notifications/devices',
      headers: {'Authorization': 'Bearer $accessToken'},
      data: {
        'installation_id': installationId,
        'token': token,
        'platform': platform,
      },
    );
    _check(response);
  }

  Future<void> unregister({
    required String accessToken,
    required String installationId,
  }) async {
    final response = await _client.delete(
      '/api/notifications/devices/${Uri.encodeComponent(installationId)}',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    _check(response);
  }

  void _check(ApiResponse response) {
    // ApiClient คืน HTTP error เป็น response จึงต้องตรวจสถานะก่อนถือว่าผูกเครื่องสำเร็จ
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationDeviceException(response.statusCode);
    }
  }

  void close() => _client.close();
}
