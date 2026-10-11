import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/identity/data/identity_api_repository.dart';

class SessionClient implements ApiClient {
  String? path;
  Map<String, dynamic>? data;
  Map<String, String>? headers;

  @override
  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    this.path = path;
    this.data = data;
    this.headers = headers;
    return const ApiResponse(statusCode: 200, data: {'id': 'test-session'});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(AuthSession.clear);

  for (final birthDate in ['2000-01-01', '${DateTime.now().year - 10}-01-01']) {
    test(
      'เริ่มรอบด้วยวันเกิด $birthDate และความยินยอม ไม่ใช้คำตอบช่วงอายุ',
      () async {
        AuthSession.saveAccessToken('test-token');
        final client = SessionClient();
        final session = await IdentityApiRepository(
          client: client,
        ).begin(birthDate);
        expect(client.path, '/api/identity/sessions');
        expect(client.data, {
          'birth_date': birthDate,
          'consent_version': 'identity-v1',
        });
        expect(client.headers, {'Authorization': 'Bearer test-token'});
        expect(session['id'], 'test-session');
      },
    );
  }
}
