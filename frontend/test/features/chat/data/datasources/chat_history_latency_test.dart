import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:frontend/features/chat/domain/entities/chat_message.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AuthenticatedClient extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

class _HistoryFixture {
  _HistoryFixture({this.holdSigning = false, this.includeImage = true}) {
    network = SupabaseClient(
      'https://project.test',
      'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path == '/rest/v1/chat_message_tb') {
          historyRequests++;
          return http.Response(
            jsonEncode([
              {
                'id': 'text',
                'conversation_id': 'room',
                'sender_id': 'other',
                'message': 'Latest ready text',
                'created_at': '2026-10-20T10:01:00Z',
              },
              if (includeImage)
                {
                  'id': 'photo',
                  'conversation_id': 'room',
                  'sender_id': 'other',
                  'message': 'Photo',
                  'image_url':
                      'https://project.test/storage/v1/object/sign/chat_bk/room/photo.jpg?token=expired',
                  'created_at': '2026-10-20T10:00:00Z',
                },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        expect(
          request.url.path,
          '/storage/v1/object/sign/chat_bk/room/photo.jpg',
        );
        signRequests++;
        if (!signingStarted.isCompleted) signingStarted.complete();
        if (holdSigning) await finishSigning.future;
        return http.Response(
          '{"signedURL":"/object/sign/chat_bk/room/photo.jpg?token=fresh"}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final auth = _Auth();
    when(() => authenticated.auth).thenReturn(auth);
    when(() => authenticated.storage).thenReturn(network.storage);
    when(() => authenticated.schema(any())).thenAnswer(
      (call) => network.schema(call.positionalArguments.single as String),
    );
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'viewer',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
  }

  final bool holdSigning;
  final bool includeImage;
  final signingStarted = Completer<void>();
  final finishSigning = Completer<void>();
  final authenticated = _AuthenticatedClient();
  late final SupabaseClient network;
  int historyRequests = 0;
  int signRequests = 0;
}

void main() {
  test('text-only history needs no image response', () async {
    final fixture = _HistoryFixture(holdSigning: true, includeImage: false);
    addTearDown(fixture.network.dispose);
    final messages = await ChatRemoteDataSource(
      client: fixture.authenticated,
    ).fetchMessages(conversationId: 'room');
    expect(messages.map((message) => message.id), ['text']);
    expect(fixture.historyRequests, 1);
    expect(fixture.signRequests, 0);
  });

  test(
    'ready text history returns while image signing is still pending',
    () async {
      final fixture = _HistoryFixture(holdSigning: true);
      addTearDown(fixture.network.dispose);
      List<ChatMessage>? availableMessages;
      final history = ChatRemoteDataSource(client: fixture.authenticated)
          .fetchMessages(conversationId: 'room')
          .then((messages) => availableMessages = messages);

      await Future.any([
        fixture.signingStarted.future,
        history,
      ]).timeout(const Duration(seconds: 2));
      expect(fixture.historyRequests, 1);
      // กั้นเฉพาะเครือข่ายรูปไว้ แต่ปล่อยคิวงานข้อความให้ทำต่อครบหนึ่งรอบ
      await Future<void>.delayed(Duration.zero);
      final textAvailableWhileSigning =
          availableMessages?.any((message) => message.id == 'text') ?? false;

      fixture.finishSigning.complete();
      await history.timeout(const Duration(seconds: 2));
      expect(availableMessages?.map((message) => message.id), [
        'photo',
        'text',
      ]);
      // ignore: avoid_print
      print(
        'History baseline: text available while signing is held='
        '$textAvailableWhileSigning; '
        'available after signing is released=${availableMessages != null}; '
        'history requests=${fixture.historyRequests}; '
        'signing requests=${fixture.signRequests}.',
      );
      expect(
        textAvailableWhileSigning,
        isTrue,
        reason:
            'Ready text must not wait for a separate image signing request '
            '(the image response is held by an explicit completion gate).',
      );
    },
  );

  test('repeated history fetch request count baseline', () async {
    final fixture = _HistoryFixture();
    addTearDown(fixture.network.dispose);
    final source = ChatRemoteDataSource(client: fixture.authenticated);
    await source.fetchMessages(conversationId: 'room');
    await source.fetchMessages(conversationId: 'room');
    expect(fixture.historyRequests, 2);
    expect(fixture.signRequests, 1);
    final signingRequestsBeforeReopen = fixture.signRequests;

    await ChatRemoteDataSource(
      client: fixture.authenticated,
    ).fetchMessages(conversationId: 'room');
    // ignore: avoid_print
    print(
      'Repeated history baseline: two fetches on one datasource '
      'history requests=2; signing requests=$signingRequestsBeforeReopen; '
      'after reopening with a new datasource history requests='
      '${fixture.historyRequests}; signing requests=${fixture.signRequests}.',
    );
    expect(fixture.historyRequests, 3);
    expect(fixture.signRequests, 1);
  });
}
