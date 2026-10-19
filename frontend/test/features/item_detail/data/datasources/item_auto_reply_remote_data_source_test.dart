import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/item_detail/data/datasources/item_auto_reply_remote_data_source.dart';
import 'package:frontend/features/item_detail/domain/entities/item_auto_reply.dart';
import 'package:mocktail/mocktail.dart';

class _Api extends Mock implements ApiClient {}

void main() {
  late _Api api;
  late ItemAutoReplyRemoteDataSource remote;
  setUp(() {
    api = _Api();
    remote = ItemAutoReplyRemoteDataSource(apiClient: api);
    AuthSession.saveAccessToken('owner-token');
  });
  tearDown(AuthSession.clear);
  test('load uses owner bearer and parses settings', () async {
    when(
      () => api.get('/api/items/7/auto-reply', headers: any(named: 'headers')),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {'enabled': true, 'message': 'สวัสดี'},
      ),
    );
    expect(
      await remote.load(7),
      const ItemAutoReply(enabled: true, message: 'สวัสดี'),
    );
    verify(
      () => api.get(
        '/api/items/7/auto-reply',
        headers: {'Authorization': 'Bearer owner-token'},
      ),
    ).called(1);
  });
  test('save retains explicit false and text in Go payload', () async {
    when(
      () => api.put(
        '/api/items/7/auto-reply',
        headers: any(named: 'headers'),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => const ApiResponse(
        statusCode: 200,
        data: {'enabled': false, 'message': 'เก็บไว้'},
      ),
    );
    await remote.save(7, const ItemAutoReply(message: 'เก็บไว้'));
    verify(
      () => api.put(
        '/api/items/7/auto-reply',
        headers: {'Authorization': 'Bearer owner-token'},
        data: {'enabled': false, 'message': 'เก็บไว้'},
      ),
    ).called(1);
  });
  test('server rejection is not reported as saved', () async {
    when(
      () => api.put(
        '/api/items/7/auto-reply',
        headers: any(named: 'headers'),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async =>
          const ApiResponse(statusCode: 404, data: {'error': 'ไม่ใช่เจ้าของ'}),
    );
    await expectLater(
      remote.save(7, const ItemAutoReply()),
      throwsA(
        isA<ItemAutoReplyException>().having(
          (e) => e.message,
          'message',
          'ไม่ใช่เจ้าของ',
        ),
      ),
    );
  });
  test('without session does not send a request', () async {
    AuthSession.clear();
    await expectLater(remote.load(7), throwsA(isA<ItemAutoReplyException>()));
    verifyZeroInteractions(api);
  });
}
