import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:frontend/features/profile/data/datasources/rental_contact_remote_data_source.dart';

class ContactChat extends ChatRemoteDataSource {
  final requested = <String>[];
  @override
  Future<String> getConversationContactPhone(String id) async {
    requested.add(id);
    return '+66987654321';
  }
}

void main() {
  test(
    'booking resolves its participants and uses authorized chat contact',
    () async {
      final queries = <Uri>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        queries.add(request.uri);
        Object data;
        if (request.uri.path.endsWith('booking_tb')) {
          data = {'user_id': 'renter', 'item_id': 7};
        } else if (request.uri.path.endsWith('item_tb')) {
          data = {'user_id': 'owner'};
        } else {
          expect(request.headers.value('accept-profile'), 'messaging');
          data = [
            {'id': 'actual-conversation'},
          ];
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      final chat = ContactChat();
      final source = RentalContactRemoteDataSource(client: client, chat: chat);
      expect(
        await source.getPhone(bookingId: 25, conversationId: 'stale'),
        '+66987654321',
      );
      expect(chat.requested, ['actual-conversation']);
      expect(queries.first.queryParameters['id'], 'eq.25');
      expect(queries[1].queryParameters['id'], 'eq.7');
      expect(
        queries.last.queryParameters['or'],
        '(and(renter_id.eq.renter,owner_id.eq.owner),and(renter_id.eq.owner,owner_id.eq.renter))',
      );
    },
  );

  test(
    'direct conversation and missing contact never use a sample number',
    () async {
      final chat = ContactChat();
      final source = RentalContactRemoteDataSource(chat: chat);
      expect(
        await source.getPhone(conversationId: 'from-booking-data'),
        '+66987654321',
      );
      await expectLater(source.getPhone(), throwsA(isA<ChatRemoteException>()));
      expect(chat.requested, ['from-booking-data']);
    },
  );
}
