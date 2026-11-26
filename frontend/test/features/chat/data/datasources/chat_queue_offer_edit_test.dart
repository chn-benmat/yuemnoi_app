import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const original = 'รายละเอียด\n[BOOKING_DATA:{"itemId":7,"status":"pending"}]';
  const updated =
      'รายละเอียดใหม่\n[BOOKING_DATA:{"itemId":7,"status":"pending"}]';

  for (final saved in [true, false]) {
    test(
      'queue offer edits only the original chat message (saved: $saved)',
      () async {
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'https://chat.test',
          'test-key',
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              saved ? '[{"id":663}]' : '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);

        final edit = ChatRemoteDataSource(client: client).editRentalQueueOffer(
          messageId: '663',
          conversationId: 'room',
          originalMessage: original,
          newMessage: updated,
        );
        if (saved) {
          await edit;
        } else {
          await expectLater(edit, throwsA(isA<ChatRemoteException>()));
        }

        final request = requests.single;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/rest/v1/chat_message_tb');
        expect(request.headers['content-profile'], 'messaging');
        expect(request.url.queryParameters, {
          'id': 'eq.663',
          'conversation_id': 'eq.room',
          'message': 'eq.$original',
          'select': 'id',
        });
        expect(jsonDecode(request.body), {'message': updated});
      },
    );
  }
}
