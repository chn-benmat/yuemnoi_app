import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/wallet_info.dart';
import '../../domain/entities/wallet_top_up_checkout.dart';
import '../models/wallet_models.dart';

class WalletRemoteException implements Exception {
  const WalletRemoteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WalletRemoteDataSource {
  WalletRemoteDataSource({ApiClient? client})
      : _client = client ?? DioApiClient();

  final ApiClient _client;

  Future<WalletInfo> getWalletInfo() async {
    final token = _requiredToken();
    try {
      final response = await _client.get(
        '/api/v1/wallet',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return WalletModels.infoFromJson(_map(response.data));
      }

      if (response.statusCode == 404) {
        // Fallback default info if wallet not yet created in backend
        return const WalletInfo(balance: 0.0, transactions: []);
      }

      throw WalletRemoteException(_serverMessage(response));
    } on ApiClientException catch (error) {
      throw WalletRemoteException(_networkMessage(error));
    } on FormatException {
      throw const WalletRemoteException('ข้อมูลกระเป๋าเงินไม่ถูกต้อง');
    }
  }

  Future<WalletTopUpCheckout> startTopUp({required double amount}) async {
    final token = _requiredToken();
    if (amount <= 0) {
      throw const WalletRemoteException('จำนวนเงินที่ต้องการเติมต้องมากกว่า 0 บาท');
    }

    try {
      final response = await _client.post(
        '/api/v1/wallet/topup-session',
        data: {
          'amount': amount,
          'amount_satang': (amount * 100).round(),
          'currency': 'thb',
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return WalletModels.topUpCheckoutFromJson(_map(response.data));
      }

      throw WalletRemoteException(_serverMessage(response));
    } on ApiClientException catch (error) {
      throw WalletRemoteException(_networkMessage(error));
    } on FormatException {
      throw const WalletRemoteException('ข้อมูลการเติมเงินที่ได้รับไม่ถูกต้อง');
    }
  }

  Future<bool> payRentalWithWallet({required int rentalId}) async {
    final token = _requiredToken();
    try {
      final response = await _client.post(
        '/api/v1/rentals/$rentalId/pay-wallet',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }

      throw WalletRemoteException(_serverMessage(response));
    } on ApiClientException catch (error) {
      throw WalletRemoteException(_networkMessage(error));
    }
  }

  String _requiredToken() {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const WalletRemoteException('กรุณาเข้าสู่ระบบก่อนทำรายการ');
    }
    return token;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Expected JSON object');
  }

  String _serverMessage(ApiResponse response) {
    final data = response.data;
    if (data is Map && data['error'] is String) {
      final message = (data['error'] as String).trim();
      if (message.isNotEmpty) return message;
    }
    if (response.statusCode == 401) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง';
    }
    return 'ไม่สามารถดำเนินการได้ กรุณาลองใหม่';
  }

  String _networkMessage(ApiClientException error) => switch (error.type) {
    ApiClientErrorType.timeout => 'ระบบชำระเงินใช้เวลานานเกินไป กรุณาลองใหม่',
    ApiClientErrorType.connection => 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้',
    ApiClientErrorType.invalidResponse => 'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง',
  };

  void close() => _client.close();
}
