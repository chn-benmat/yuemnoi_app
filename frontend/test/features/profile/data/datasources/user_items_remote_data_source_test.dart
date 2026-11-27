import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/datasources/user_items_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:mocktail/mocktail.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  test('receives owner broadcasts and resyncs after reconnecting', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final joins = StreamController<(WebSocket, List<dynamic>)>();
    final sockets = <WebSocket>[];
    final left = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((message) {
        final frame = jsonDecode(message as String) as List<dynamic>;
        socket.add(
          jsonEncode([
            frame[0],
            frame[1],
            frame[2],
            'phx_reply',
            {'status': 'ok', 'response': <String, dynamic>{}},
          ]),
        );
        if (frame[3] == 'phx_join') joins.add((socket, frame));
        if (frame[3] == 'phx_leave') left.complete();
      });
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'sb_publishable_test',
    );
    final connection = StreamIterator(joins.stream);
    final source = UserItemsRemoteDataSource(client: client);
    final changes = StreamIterator(source.watchMyItemChanges('owner'));
    addTearDown(() async {
      await changes.cancel();
      await connection.cancel();
      await client.dispose();
      await Future.wait(sockets.map((socket) => socket.close()));
      await server.close(force: true);
      await joins.close();
    });

    final initialSync = changes.moveNext();
    expect(await connection.moveNext(), isTrue);
    final (socket, join) = connection.current;
    expect(join[2], 'realtime:my_items:owner');
    expect(join[4]['config']['private'], isTrue);
    expect(await initialSync, isTrue);

    final changed = changes.moveNext();
    socket.add(
      jsonEncode([
        join[0],
        null,
        join[2],
        'broadcast',
        {'type': 'broadcast', 'event': 'items_changed', 'payload': {}},
      ]),
    );
    expect(await changed, isTrue);

    final reconnectSync = changes.moveNext();
    await socket.close();
    expect(await connection.moveNext(), isTrue);
    expect(await reconnectSync, isTrue);
    await changes.cancel();
    await left.future;
  });

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
          containsAll(['status', 'type', 'owner_hidden', 'is_rental_occupied']),
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
                  'is_rental_occupied': offset == 0,
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
      expect(items.first.isRentalOccupied, isTrue);
      expect(items.last.isRentalOccupied, isFalse);
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
