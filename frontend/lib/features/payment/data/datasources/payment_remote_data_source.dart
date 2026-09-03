import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/payment.dart';
import '../models/payment_models.dart';

class PaymentRemoteException implements Exception {
  const PaymentRemoteException(this.message);

  final String message;
}

class PaymentRemoteDataSource {
  PaymentRemoteDataSource({ApiClient? client})
    : _client = client ?? DioApiClient();

  final ApiClient _client;
  int? _pendingRentalId;

  Future<PaymentCheckout> startCheckout(PaymentRentalDraft draft) async {
    final token = _requiredToken();
    try {
      var rentalId = _pendingRentalId;
      if (rentalId == null) {
        final rentalResponse = await _client.post(
          '/api/v1/rentals',
          data: {
            'item_id': draft.itemId,
            'start_at': draft.startAt.toUtc().toIso8601String(),
            'end_at': draft.endAt.toUtc().toIso8601String(),
            'rental_type': draft.rentalType,
            'pickup_location': draft.pickupLocation.trim(),
          },
          headers: {'Authorization': 'Bearer $token'},
        );
        if (rentalResponse.statusCode != 201) {
          throw PaymentRemoteException(_serverMessage(rentalResponse));
        }
        final rentalData = _map(rentalResponse.data);
        rentalId = _int(rentalData['id']);
        if (rentalId == null || rentalId <= 0) {
          throw const PaymentRemoteException('ข้อมูลการจองที่ได้รับไม่ถูกต้อง');
        }
        _pendingRentalId = rentalId;
      }

      final checkoutResponse = await _client.post(
        '/api/v1/rentals/$rentalId/checkout-session',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (checkoutResponse.statusCode != 201) {
        throw PaymentRemoteException(_serverMessage(checkoutResponse));
      }
      return PaymentModels.checkoutFromJson(_map(checkoutResponse.data));
    } on ApiClientException catch (error) {
      throw PaymentRemoteException(_networkMessage(error));
    } on FormatException {
      throw const PaymentRemoteException(
        'ข้อมูลการชำระเงินที่ได้รับไม่ถูกต้อง',
      );
    }
  }

  Future<int> createRental(PaymentRentalDraft draft) async {
    final token = _requiredToken();
    try {
      if (_pendingRentalId != null && _pendingRentalId! > 0) {
        return _pendingRentalId!;
      }
      final rentalResponse = await _client.post(
        '/api/v1/rentals',
        data: {
          'item_id': draft.itemId,
          'start_at': draft.startAt.toUtc().toIso8601String(),
          'end_at': draft.endAt.toUtc().toIso8601String(),
          'rental_type': draft.rentalType,
          'pickup_location': draft.pickupLocation.trim(),
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      if (rentalResponse.statusCode != 201) {
        throw PaymentRemoteException(_serverMessage(rentalResponse));
      }
      final rentalData = _map(rentalResponse.data);
      final rentalId = _int(rentalData['id']);
      if (rentalId == null || rentalId <= 0) {
        throw const PaymentRemoteException('ข้อมูลการจองที่ได้รับไม่ถูกต้อง');
      }
      _pendingRentalId = rentalId;
      return rentalId;
    } on ApiClientException catch (error) {
      throw PaymentRemoteException(_networkMessage(error));
    } on FormatException {
      throw const PaymentRemoteException('ข้อมูลการจองไม่ถูกต้อง');
    }
  }

  Future<bool> payWithWallet(int rentalId) async {
    final token = _requiredToken();
    try {
      final response = await _client.post(
        '/api/v1/rentals/$rentalId/pay-wallet',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
      throw PaymentRemoteException(_serverMessage(response));
    } on ApiClientException catch (error) {
      throw PaymentRemoteException(_networkMessage(error));
    }
  }

  Future<RentalPaymentStatus> getStatus(int rentalId) async {
    final token = _requiredToken();
    try {
      final response = await _client.get(
        '/api/v1/rentals/$rentalId/payment-status',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw PaymentRemoteException(_serverMessage(response));
      }
      return PaymentModels.statusFromJson(_map(response.data));
    } on ApiClientException catch (error) {
      throw PaymentRemoteException(_networkMessage(error));
    } on FormatException {
      throw const PaymentRemoteException('ข้อมูลสถานะการชำระเงินไม่ถูกต้อง');
    }
  }

  String _requiredToken() {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const PaymentRemoteException('กรุณาเข้าสู่ระบบก่อนชำระเงิน');
    }
    return token;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Expected JSON object');
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
    return 'ไม่สามารถเริ่มการชำระเงินได้ กรุณาลองใหม่';
  }

  String _networkMessage(ApiClientException error) => switch (error.type) {
    ApiClientErrorType.timeout => 'ระบบชำระเงินใช้เวลานานเกินไป กรุณาลองใหม่',
    ApiClientErrorType.connection => 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้',
    ApiClientErrorType.invalidResponse => 'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง',
  };

  void close() => _client.close();
}
