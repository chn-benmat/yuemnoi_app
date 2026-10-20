import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AuthenticatedClient extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

void main() {
  test('chat stream uses messaging for REST and Realtime', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final joined = Completer<List<dynamic>>();
    final fetched = Completer<void>();
    final sockets = <WebSocket>[];
    var shuttingDown = false;
    StreamSubscription<dynamic>? subscription;
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((message) {
          if (shuttingDown) return;
          final frame = jsonDecode(message as String) as List;
          final event = frame[3];
          if (event != 'phx_join' && event != 'phx_leave') return;
          if (socket.readyState != WebSocket.open) return;
          var response = <String, dynamic>{};
          if (event == 'phx_join') {
            final changes = frame[4]['config']['postgres_changes'] as List;
            if (!joined.isCompleted) joined.complete(changes);
            response = {
              'postgres_changes': [
                for (final (index, change) in changes.indexed)
                  {...change as Map, 'id': index},
              ],
            };
          }
          socket.add(
            jsonEncode([
              frame[0],
              frame[1],
              frame[2],
              'phx_reply',
              {'status': 'ok', 'response': response},
            ]),
          );
        });
        return;
      }
      expect(request.uri.path, '/rest/v1/chat_message_tb');
      expect(request.headers.value('accept-profile'), 'messaging');
      expect(request.uri.queryParameters['conversation_id'], 'eq.room-id');
      request.response.headers.contentType = ContentType.json;
      request.response.write('[]');
      await request.response.close();
      if (!fetched.isCompleted) fetched.complete();
    });
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
    );
    final authenticated = _AuthenticatedClient();
    final auth = _Auth();
    when(() => authenticated.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'sender-id',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
    when(() => authenticated.schema(any())).thenAnswer(
      (call) => client.schema(call.positionalArguments.single as String),
    );
    addTearDown(() async {
      shuttingDown = true;
      await subscription?.cancel();
      await client.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    final source = ChatRemoteDataSource(client: authenticated);
    subscription = source.streamMessages('room-id').listen((_) {});
    final changes = await joined.future.timeout(const Duration(seconds: 5));
    await fetched.future.timeout(const Duration(seconds: 5));
    expect(changes.single['schema'], 'messaging');
    expect(changes.single['table'], 'chat_message_tb');
    expect(changes.single['filter'], 'conversation_id=eq.room-id');
  });
}
