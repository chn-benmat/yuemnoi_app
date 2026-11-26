import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/identity/data/identity_api_repository.dart';

class SessionClient implements ApiClient {
  String? path;
  Map<String, dynamic>? data;
  Map<String, String>? headers;
  Map<String, String>? submittedFields;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async => const ApiResponse(statusCode: 200, data: {});

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
  Future<ApiResponse> postMultipart(
    String path, {
    Map<String, String>? fields,
    List<ApiUpload> files = const [],
    Map<String, String>? headers,
  }) async {
    submittedFields = fields;
    return const ApiResponse(statusCode: 201, data: {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(AuthSession.clear);

  for (final updatingAccount in [false, true]) {
    test(
      'ส่งเวอร์ชันข้อความเก็บรูปเมื่อส่งคำขอ (แก้ไข: $updatingAccount)',
      () async {
        AuthSession.saveAccessToken('test-token');
        final client = SessionClient();
        final repository = IdentityApiRepository(client: client);
        final fields = {'birth_date': '2000-01-01'};

        if (updatingAccount) {
          await repository.updateAccount(fields, card: Uint8List(1));
        } else {
          await repository.submit(
            'test-session',
            fields,
            Uint8List(1),
            Uint8List(1),
          );
        }

        expect(client.submittedFields!['consent_version'], 'identity-v2');
      },
    );
  }

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
