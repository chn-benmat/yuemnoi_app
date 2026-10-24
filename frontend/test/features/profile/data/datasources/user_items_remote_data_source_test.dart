import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/datasources/user_items_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  test(
    'reads every owner page with status/unit and propagates query failures',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var fail = false;
      final offsets = <int>[];
      server.listen((request) async {
        final query = request.uri.queryParameters;
        expect(query['user_id'], 'eq.owner');
        expect(
          query['select']!.split(',').map((column) => column.trim()),
          containsAll(['status', 'type', 'owner_hidden']),
        );
        expect(query['order'], startsWith('id.desc'));
        request.response.headers.contentType = ContentType.json;
        if (fail) {
          request.response.statusCode = 403;
          request.response.write(
            jsonEncode({'message': 'permission denied', 'code': '42501'}),
          );
        } else {
          final offset = int.parse(query['offset'] ?? '0');
          offsets.add(offset);
          request.response.write(
            jsonEncode(
              List.generate(
                offset == 0 ? 500 : 1,
                (index) => {
                  'id': 501 - offset - index,
                  'item_name': 'Camera',
                  'status': 'available',
                  'owner_hidden': true,
                  'type': 'รายชั่วโมง',
                },
              ),
            ),
          );
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-anon-key',
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final source = UserItemsRemoteDataSource(client: client);
      final items = await source.getMyItems('owner');
      expect(items.length, 501);
      expect(offsets, [0, 500]);
      expect(items.first.status, 'available');
      expect(items.first.ownerHidden, isTrue);
      expect(items.last.rentalType, 'รายชั่วโมง');
      fail = true;
      await expectLater(
        source.getMyItems('owner'),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
  test('favorites retain the account name belonging to each item', () async {
    final api = _MockApiClient();
    for (final id in [11, 22]) {
      when(() => api.get('/api/items/$id')).thenAnswer(
        (_) async => ApiResponse(
          statusCode: 200,
          data: {
            'id': id,
            'user_id': 'owner-$id',
            'item_name': 'Item $id',
            'owner_name': 'Account $id',
          },
        ),
      );
    }
    when(
      () => api.get('/api/items/33'),
    ).thenAnswer((_) async => const ApiResponse(statusCode: 404, data: {}));
    final source = UserItemsRemoteDataSource(
      apiClient: api,
      getFavoriteIds: () async => [22, 33, 11],
    );

    final items = await source.getFavorites();

    expect(items.map((item) => item.id), [22, 11]);
    expect(items.map((item) => item.toEntity().ownerName), [
      'Account 22',
      'Account 11',
    ]);
  });

  test('API failures are reported instead of showing an empty list', () async {
    final api = _MockApiClient();
    when(
      () => api.get('/api/items/11'),
    ).thenAnswer((_) async => const ApiResponse(statusCode: 500, data: {}));
    final source = UserItemsRemoteDataSource(
      apiClient: api,
      getFavoriteIds: () async => [11],
    );
    await expectLater(
      source.getFavorites(),
      throwsA(isA<ApiClientException>()),
    );
  });
}
