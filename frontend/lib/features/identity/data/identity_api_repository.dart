import 'dart:typed_data';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_session.dart';
import '../domain/identity_repository.dart';

class IdentityApiRepository implements IdentityRepository {
  IdentityApiRepository({ApiClient? client})
    : _client =
          client ?? DioApiClient(requestTimeout: const Duration(seconds: 120));
  final ApiClient _client;
  Map<String, String> get _headers {
    final token = AuthSession.accessToken;
    if (token == null || token.isEmpty) {
      throw const IdentityFailure('กรุณาเข้าสู่ระบบอีกครั้ง');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _result(ApiResponse r) {
    if (r.statusCode >= 200 && r.statusCode < 300 && r.data is Map) {
      return Map<String, dynamic>.from(r.data);
    }
    throw IdentityFailure(
      r.data is Map && r.data['error'] is String
          ? r.data['error']
          : 'ไม่สามารถดำเนินการได้ กรุณาลองใหม่',
    );
  }

  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiClientException {
      throw const IdentityFailure('เชื่อมต่อระบบไม่ได้ กรุณาลองใหม่');
    }
  }

  @override
  Future<IdentityStatus> status() => _call(
    () async => IdentityStatus(
      _result(await _client.get('/api/identity/status', headers: _headers)),
    ),
  );
  @override
  Future<Map<String, dynamic>> begin(String birthDate) => _call(
    () async => _result(
      await _client.post(
        '/api/identity/sessions',
        headers: _headers,
        data: {'birth_date': birthDate, 'consent_version': 'identity-v1'},
      ),
    ),
  );
  @override
  Future<void> submit(
    String session,
    Map<String, String> fields,
    Uint8List card,
    Uint8List selfie,
  ) => _call(() async {
    _result(
      await _client.postMultipart(
        '/api/identity/sessions/$session/submit',
        headers: _headers,
        fields: fields,
        files: [
          ApiUpload(fieldName: 'card', bytes: card, fileName: 'card.jpg'),
          ApiUpload(fieldName: 'selfie', bytes: selfie, fileName: 'selfie.jpg'),
        ],
      ),
    );
  });
  @override
  void close() => _client.close();
}
