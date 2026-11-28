import '../../../core/network/api_client.dart';
import '../domain/app_notification.dart';

class NotificationRemoteDataSource {
  NotificationRemoteDataSource({ApiClient? client})
    : _client = client ?? DioApiClient();

  final ApiClient _client;

  Future<List<AppNotification>> fetch(
    String token, {
    required int limit,
    required int offset,
  }) async {
    final response = await _client.get(
      '/api/notifications',
      headers: {'Authorization': 'Bearer $token'},
      queryParameters: {'limit': limit, 'offset': offset},
    );
    _check(response);
    final items = (response.data as Map)['items'] as List;
    return items
        .map(
          (row) =>
              AppNotification.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> markRead(String token, String id) async {
    _check(
      await _client.post(
        '/api/notifications/${Uri.encodeComponent(id)}/read',
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
  }

  void _check(ApiResponse response) {
    if (response.statusCode != 200) {
      throw StateError('notification_api_unavailable');
    }
  }

  void close() => _client.close();
}
