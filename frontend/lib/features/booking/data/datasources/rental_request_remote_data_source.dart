import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../../identity/domain/rental_verification.dart';
import '../../domain/entities/rental_request.dart';

class RentalRequestRemoteException implements Exception {
  const RentalRequestRemoteException(this.message);

  final String message;
}

class RentalRequestRemoteDataSource {
  RentalRequestRemoteDataSource({ApiClient? client})
    : _client = client ?? DioApiClient();

  final ApiClient _client;

  Future<RentalRequestResult> submit(RentalRequestDraft draft) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const RentalRequestRemoteException(
        'กรุณาเข้าสู่ระบบก่อนส่งคำขอเช่า',
      );
    }

    try {
      final response = await _client.post(
        '/api/rentals',
        data: {
          'item_id': draft.itemId,
          'start_at': draft.startAt.toUtc().toIso8601String(),
          'end_at': draft.endAt.toUtc().toIso8601String(),
          'rental_type': draft.rentalType,
          'pickup_location': draft.pickupLocation.trim(),
          if (draft.offerMessageId != null)
            'offer_message_id': draft.offerMessageId,
          if (draft.bookingId != null) 'booking_id': draft.bookingId,
          if (draft.conversationId != null)
            'conversation_id': draft.conversationId,
          if (draft.paymentMethod != null)
            'payment_method': draft.paymentMethod,
          if (draft.unitPrice != null) 'unit_price': draft.unitPrice,
          if (draft.queueMessageId != null)
            'queue_message_id': draft.queueMessageId,
          'request_revision': ?draft.requestRevision,
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      final isEdit = draft.conversationId != null && draft.bookingId != null;
      if (response.statusCode != (isEdit ? 200 : 201)) {
        final blocked = RentalVerificationRequired.fromJson(response.data);
        if (blocked != null) throw blocked;
        throw RentalRequestRemoteException(_serverMessage(response));
      }
      final data = _map(response.data);
      final id = _int(data['id']);
      final status = data['status']?.toString() ?? '';
      if (id == null ||
          id <= 0 ||
          status.isEmpty ||
          (isEdit && (id != draft.bookingId || status != 'pending'))) {
        throw const RentalRequestRemoteException(
          'ข้อมูลคำขอเช่าที่ได้รับไม่ถูกต้อง',
        );
      }
      return RentalRequestResult(id: id, status: status);
    } on ApiClientException catch (error) {
      throw RentalRequestRemoteException(_networkMessage(error));
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const RentalRequestRemoteException(
      'ข้อมูลคำขอเช่าที่ได้รับไม่ถูกต้อง',
    );
  }

  Future<RentalRequestResult> confirm({
    required int rentalId,
    required String offerMessageId,
    required String paymentMethod,
    int? requestRevision,
  }) async {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const RentalRequestRemoteException(
        'กรุณาเข้าสู่ระบบก่อนยืนยันการเช่า',
      );
    }
    try {
      final response = await _client.post(
        '/api/rentals/$rentalId/confirm',
        data: {
          'offer_message_id': offerMessageId,
          'payment_method': paymentMethod,
          'request_revision': ?requestRevision,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw RentalRequestRemoteException(_serverMessage(response));
      }
      final data = _map(response.data);
      final id = _int(data['id']);
      final status = data['status']?.toString() ?? '';
      if (id == null || id <= 0 || status.isEmpty) {
        throw const RentalRequestRemoteException(
          'ข้อมูลการยืนยันการเช่าไม่ถูกต้อง',
        );
      }
      return RentalRequestResult(id: id, status: status);
    } on ApiClientException catch (error) {
      throw RentalRequestRemoteException(_networkMessage(error));
    }
  }

  int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  String _serverMessage(ApiResponse response) {
    final data = response.data;
    if (data is Map && data['error'] is String) {
      final message = (data['error'] as String).trim();
      if (message.isNotEmpty) return message;
    }
    if (response.statusCode == 401) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง';
    }
    return 'ไม่สามารถส่งคำขอเช่าได้ กรุณาลองใหม่';
  }

  String _networkMessage(ApiClientException error) => switch (error.type) {
    ApiClientErrorType.timeout => 'การส่งคำขอใช้เวลานานเกินไป กรุณาลองใหม่',
    ApiClientErrorType.connection => 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้',
    ApiClientErrorType.invalidResponse => 'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง',
  };

  void close() => _client.close();
}
