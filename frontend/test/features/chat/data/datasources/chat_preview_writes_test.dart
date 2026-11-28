import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Client extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

ChatRemoteDataSource _source(MockClient httpClient) {
  final network = SupabaseClient(
    'https://chat.test',
    'test-key',
    httpClient: httpClient,
  );
  addTearDown(network.dispose);
  final client = _Client();
  final auth = _Auth();
  when(() => client.auth).thenReturn(auth);
  when(() => client.schema(any())).thenAnswer(
    (call) => network.schema(call.positionalArguments.single as String),
  );
  when(() => client.storage).thenReturn(network.storage);
  return ChatRemoteDataSource(client: client);
}

http.Response _json(http.Request request, Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
  request: request,
);

void main() {
  // ฐานอัปเดต preview ของห้องเองเมื่อแก้หรือลบข้อความ แอปจึงไม่ต้องเขียน conversation_tb
  test('editing a message leaves the room preview to the database', () async {
    final paths = <String>[];
    final source = _source(
      MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        return _json(request, const []);
      }),
    );

    await source.editMessage(
      messageId: '12',
      newMessage: 'แก้ข้อความ',
      conversationId: 'room',
    );

    expect(paths, ['PATCH /rest/v1/chat_message_tb']);
  });

  test('deleting a message leaves the room preview to the database', () async {
    final paths = <String>[];
    final source = _source(
      MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        return _json(
          request,
          request.method == 'GET' ? {'image_url': null} : const [],
        );
      }),
    );

    await source.deleteMessage(messageId: '12', conversationId: 'room');

    expect(paths.where((path) => path.contains('conversation_tb')), isEmpty);
    expect(paths, contains('DELETE /rest/v1/chat_message_tb'));
  });
}
