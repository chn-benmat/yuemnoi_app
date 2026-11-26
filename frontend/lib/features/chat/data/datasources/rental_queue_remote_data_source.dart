import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';

class RentalQueueRemoteException implements Exception {
  const RentalQueueRemoteException(this.message);

  final String message;
}

class RentalQueueRemoteDataSource {
  RentalQueueRemoteDataSource({ApiClient? client})
    : _client = client ?? DioApiClient();

  final ApiClient _client;

  Future<List<({int id, String name})>> listItems(String conversationId) async {
    final result = await runAction(conversationId, 'list');
    final items = result['items'];
    if (items is! List) return [];
    return [
      for (final item in items.whereType<Map<String, dynamic>>())
        (id: item['id'] as int, name: item['name'] as String),
    ];
  }

  Future<Map<String, dynamic>> runAction(
    String conversationId,
    String action, {
    int? itemId,
    int? messageId,
  }) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const RentalQueueRemoteException(
        'กรุณาเข้าสู่ระบบก่อนใช้คิวเช่าต่อ',
      );
    }
    try {
      final response = await _client.post(
        '/api/rentals/queue',
        data: {
          'conversation_id': conversationId,
          'action': action,
          'item_id': ?itemId,
          'message_id': ?messageId,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      final result = response.data;
      if (response.statusCode == 200 && result is Map<String, dynamic>) {
        return result;
      }
      if (response.statusCode == 409) {
        throw const RentalQueueRemoteException(
          'สถานะคิวเปลี่ยนแล้ว กรุณาตรวจสอบข้อความล่าสุด',
        );
      }
      throw const RentalQueueRemoteException(
        'จัดการคิวเช่าต่อไม่สำเร็จ กรุณาลองใหม่',
      );
    } on ApiClientException {
      throw const RentalQueueRemoteException(
        'เชื่อมต่อระบบคิวเช่าต่อไม่สำเร็จ กรุณาลองใหม่',
      );
    }
  }

  void close() => _client.close();
}
