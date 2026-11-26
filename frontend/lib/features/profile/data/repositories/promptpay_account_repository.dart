import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/promptpay_account.dart';

class PromptPayAccountException implements Exception {
  const PromptPayAccountException(this.message);

  final String message;
}

class PromptPayAccountRepository {
  PromptPayAccountRepository({ApiClient? apiClient})
    : _api = apiClient ?? DioApiClient();

  static const _path = '/api/user/promptpay';
  final ApiClient _api;

  Future<PromptPayAccount> load() async {
    return _readAccount(await _api.get(_path, headers: _headers()));
  }

  Future<PromptPayAccount> save(
    String identifier, {
    required bool nationalId,
  }) async {
    return _readAccount(
      await _api.put(
        _path,
        headers: _headers(),
        data: {
          (nationalId ? 'promptpay_national_id' : 'promptpay_phone'):
              identifier,
        },
      ),
    );
  }

  void close() => _api.close();

  Map<String, String> _headers() {
    final token = AuthSession.accessToken;
    if (token == null) {
      throw const PromptPayAccountException('กรุณาเข้าสู่ระบบอีกครั้ง');
    }
    return {'Authorization': 'Bearer $token'};
  }

  PromptPayAccount _readAccount(ApiResponse response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const PromptPayAccountException('กรุณาเข้าสู่ระบบอีกครั้ง');
    }
    final data = response.data;
    if (data case {
      'error': final String message,
    } when response.statusCode == 400) {
      throw PromptPayAccountException(message);
    }
    if (response.statusCode != 200) {
      throw const FormatException('Unexpected PromptPay response status');
    }
    return switch (data) {
      {'promptpay_id_type': 'phone', 'promptpay_phone': final String phone} =>
        PromptPayAccount(phone: phone),
      {
        'promptpay_id_type': 'national_id',
        'national_id_last_four': final String lastFour,
      }
          when RegExp(r'^[0-9]{4}$').hasMatch(lastFour) =>
        PromptPayAccount.nationalId(lastFour),
      final Map<String, dynamic> account
          when account['promptpay_id_type'] == 'national_id' &&
              account['national_id_last_four'] == null =>
        const PromptPayAccount.nationalId(),
      final Map<String, dynamic> account when account.isEmpty =>
        const PromptPayAccount(),
      _ => throw const FormatException('Invalid PromptPay account'),
    };
  }
}
