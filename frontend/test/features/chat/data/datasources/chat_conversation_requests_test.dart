import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AuthenticatedClient extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

ChatRemoteDataSource _source(MockClient httpClient, {bool signedIn = true}) {
  final network = SupabaseClient(
    'https://chat.test',
    'test-key',
    httpClient: httpClient,
  );
  addTearDown(network.dispose);
  final client = _AuthenticatedClient();
  final auth = _Auth();
  when(() => client.auth).thenReturn(auth);
  when(() => client.schema(any())).thenAnswer(
    (call) => network.schema(call.positionalArguments.single as String),
  );
  when(() => client.from('item_tb')).thenAnswer((_) => network.from('item_tb'));
  when(() => auth.currentUser).thenReturn(
    signedIn
        ? const User(
            id: 'viewer',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '',
          )
        : null,
  );
  return ChatRemoteDataSource(client: client);
}

http.Response _json(
  http.Request request,
  Object data, {
  int statusCode = 200,
}) => http.Response(
  jsonEncode(data),
  statusCode,
  headers: {'content-type': 'application/json'},
  request: request,
);

void main() {
  test('mark read updates only unread incoming messages in the room', () async {
    final requests = <http.Request>[];
    final source = _source(
      MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );

    await source.markMessagesAsRead(conversationId: 'room');

    final request = requests.single;
    expect(request.method, 'PATCH');
    expect(request.url.path, '/rest/v1/chat_message_tb');
    expect(request.headers['Content-Profile'], 'messaging');
    expect(request.url.queryParameters, {
      'conversation_id': 'eq.room',
      'or': '(sender_id.neq.viewer,sender_id.is.null)',
      'is_read': 'not.is.true',
    });
    expect(jsonDecode(request.body), {'is_read': true});
  });

  test(
    'conversation reads reject a signed-out client before sending requests',
    () async {
      final requests = <http.Request>[];
      final source = _source(
        MockClient((request) async {
          requests.add(request);
          return _json(request, []);
        }),
        signedIn: false,
      );

      await expectLater(
        source.getConversations(),
        throwsA(isA<ChatRemoteException>()),
      );
      await expectLater(
        source.markMessagesAsRead(conversationId: 'room'),
        throwsA(isA<ChatRemoteException>()),
      );
      expect(requests, isEmpty);
    },
  );

  for (final profileLookupFails in [false, true]) {
    test(
      profileLookupFails
          ? 'a profile lookup failure preserves item and unread results'
          : 'profiles, items and unread badges load in parallel for visible rooms',
      () async {
        final lookups = <String, http.Request>{};
        final allLookupsStarted = Completer<void>();
        final releaseLookups = Completer<void>();
        final source = _source(
          MockClient((request) async {
            final path = request.url.path;
            if (path == '/rest/v1/conversation_tb') {
              return _json(request, [
                {
                  'id': 'latest',
                  'renter_id': 'viewer',
                  'owner_id': 'other',
                  'item_id': 10,
                },
                {'id': 'older', 'renter_id': 'viewer', 'owner_id': 'other'},
                {'id': 'deleted', 'renter_id': 'viewer', 'owner_id': null},
                {'id': 'read', 'renter_id': 'viewer', 'owner_id': 'third'},
              ]);
            }

            lookups[path] = request;
            if (lookups.length == 3 && !allLookupsStarted.isCompleted) {
              allLookupsStarted.complete();
            }
            await releaseLookups.future;
            return switch (path) {
              '/rest/v1/public_profile_v' when profileLookupFails => _json(
                request,
                {'message': 'Profile service unavailable'},
                statusCode: 400,
              ),
              '/rest/v1/public_profile_v' => _json(request, [
                {'user_id': 'other', 'display_name': 'Other User'},
                {'user_id': 'third', 'display_name': 'Third User'},
              ]),
              '/rest/v1/item_tb' => _json(request, [
                {'id': 10, 'item_name': 'Drill', 'user_id': 'other'},
              ]),
              '/rest/v1/rpc/chat_unread_conversation_ids' => _json(request, [
                {'conversation_id': 'latest'},
                {'conversation_id': 'deleted'},
              ]),
              _ => throw StateError('Unexpected request: ${request.url}'),
            };
          }),
        );

        final result = source.getConversations();
        try {
          await allLookupsStarted.future.timeout(const Duration(seconds: 2));
        } finally {
          releaseLookups.complete();
        }

        final unreadRequest =
            lookups['/rest/v1/rpc/chat_unread_conversation_ids']!;
        expect(unreadRequest.method, 'POST');
        expect(jsonDecode(unreadRequest.body), {
          'p_conversation_ids': ['latest', 'deleted', 'read'],
        });
        final rooms = await result;
        expect(rooms.map((room) => room.id), ['latest', 'deleted', 'read']);
        expect(rooms.map((room) => room.hasUnreadMessage), [true, true, false]);
        expect(rooms.first.itemName, 'Drill');
        expect(rooms.first.isOtherUserUnavailable, isFalse);
        expect(
          rooms.first.name,
          profileLookupFails ? 'ผู้ใช้งาน Yuemnoi' : 'Other User',
        );
        expect(rooms[1].isOtherUserUnavailable, isTrue);
      },
    );
  }
}
