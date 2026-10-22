import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AuthenticatedClient extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

class _ChatFixture {
  final messages = <Map<String, dynamic>>[];
  final bookings = <Map<String, dynamic>>[];
  bool failHistory = false;
  bool failNextInsert = false;
  late final SupabaseClient client;
  late final SupabaseClient authenticated;

  _ChatFixture() {
    client = SupabaseClient(
      'https://inquiry.test',
      'test-key',
      httpClient: MockClient((request) async {
        Object response;
        if (request.method == 'POST' &&
            request.url.path.endsWith('/chat_message_tb')) {
          expect(request.headers['content-profile'], 'messaging');
          if (failNextInsert) {
            failNextInsert = false;
            return http.Response(
              '{"message":"insert failed","code":"42501"}',
              400,
              request: request,
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final record = {...body, 'id': 'message-${messages.length + 1}'};
          messages.add(record);
          response = {'id': record['id']};
        } else if (request.method == 'GET' &&
            request.url.path.endsWith('/chat_message_tb')) {
          expect(request.headers['accept-profile'], 'messaging');
          if (failHistory)
            return http.Response(
              '{"message":"history unavailable","code":"42501"}',
              400,
              request: request,
            );
          expect(request.url.queryParameters['sender_id'], 'eq.customer');
          final query = request.url.queryParameters;
          final offset = int.tryParse(query['offset'] ?? '') ?? 0;
          final limit = int.tryParse(query['limit'] ?? '') ?? 100;
          response = messages.reversed
              .where(
                (message) =>
                    'eq.${message['conversation_id']}' ==
                        query['conversation_id'] &&
                    'eq.${message['sender_id']}' == query['sender_id'] &&
                    ItemInquiryData.isInquiry(message['message'] as String),
              )
              .skip(offset)
              .take(limit)
              .toList();
        } else if (request.method == 'GET' &&
            request.url.path.endsWith('/booking_tb')) {
          expect(request.url.queryParameters['user_id'], 'eq.customer');
          expect(
            request.url.queryParameters['order'],
            contains('created_at.desc'),
          );
          response = bookings.reversed
              .where(
                (booking) =>
                    'eq.${booking['item_id']}' ==
                    request.url.queryParameters['item_id'],
              )
              .take(1)
              .toList();
        } else {
          throw StateError('Unexpected ${request.method} ${request.url.path}');
        }
        return http.Response(
          jsonEncode(response),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    authenticated = _AuthenticatedClient();
    final auth = _Auth();
    when(() => authenticated.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'customer',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '',
      ),
    );
    when(() => authenticated.schema(any())).thenAnswer(
      (call) => client.schema(call.positionalArguments.single as String),
    );
    when(() => authenticated.from(any())).thenAnswer(
      (call) => client.from(call.positionalArguments.single as String),
    );
  }

  Future<void> openItemChat({int itemId = 1}) =>
      ChatRemoteDataSource(client: authenticated).sendItemInquiryIfNeeded(
        conversationId: 'room',
        inquiry: ItemInquiryData(itemId: itemId, itemName: 'Canon EOS R50'),
      );

  void addBooking(String status, {int id = 10, int itemId = 1}) {
    bookings.add({
      'id': id,
      'item_id': itemId,
      'user_id': 'customer',
      'status': status,
    });
  }
}

void main() {
  test('reopening the same item chat saves only one inquiry', () async {
    final fixture = _ChatFixture();
    addTearDown(fixture.client.dispose);
    await fixture.openItemChat();
    await fixture.openItemChat();
    expect(
      fixture.messages,
      hasLength(1),
      reason:
          'Opening an existing item chat must not send the interest card again.',
    );
  });

  for (final status in [
    'pending',
    'confirmed',
    'active',
    'awaiting_return',
    'return_ready',
  ]) {
    test('reopening during $status does not start another inquiry', () async {
      final fixture = _ChatFixture();
      addTearDown(fixture.client.dispose);
      await fixture.openItemChat();
      fixture.addBooking(status);
      await fixture.openItemChat();
      expect(fixture.messages, hasLength(1));
    });
  }

  for (final status in ['completed', 'cancelled']) {
    test(
      'a $status rental allows one inquiry for the next rental cycle',
      () async {
        final fixture = _ChatFixture();
        addTearDown(fixture.client.dispose);
        await fixture.openItemChat();
        fixture.addBooking(status);
        await fixture.openItemChat();
        await fixture.openItemChat();
        expect(fixture.messages, hasLength(2));
        expect(
          fixture.messages.last['message'],
          contains('"previousBookingId":10'),
        );
        fixture.addBooking('completed', id: 11);
        await fixture.openItemChat();
        await fixture.openItemChat();
        expect(fixture.messages, hasLength(3));
        expect(
          fixture.messages.last['message'],
          contains('"previousBookingId":11'),
        );
      },
    );
  }

  test(
    'different items in the same conversation have separate inquiries',
    () async {
      final fixture = _ChatFixture();
      addTearDown(fixture.client.dispose);
      await fixture.openItemChat();
      await fixture.openItemChat(itemId: 2);
      await fixture.openItemChat();
      expect(fixture.messages, hasLength(2));
    },
  );

  test(
    'simultaneous entry through separate datasource instances sends once',
    () async {
      final fixture = _ChatFixture();
      addTearDown(fixture.client.dispose);
      await Future.wait([fixture.openItemChat(), fixture.openItemChat()]);
      expect(fixture.messages, hasLength(1));
    },
  );

  test('finds an earlier item inquiry beyond the first history page', () async {
    final fixture = _ChatFixture();
    addTearDown(fixture.client.dispose);
    await fixture.openItemChat();
    for (var itemId = 2; itemId < 103; itemId++) {
      fixture.messages.add({
        'id': 'history-$itemId',
        'conversation_id': 'room',
        'sender_id': 'customer',
        'message': ItemInquiryData(
          itemId: itemId,
          itemName: 'อุปกรณ์ $itemId',
        ).toChatMessagePayload(),
      });
    }
    await fixture.openItemChat();
    expect(fixture.messages, hasLength(102));
  });

  test('history failure does not create an unchecked duplicate', () async {
    final fixture = _ChatFixture();
    addTearDown(fixture.client.dispose);
    await fixture.openItemChat();
    fixture.failHistory = true;
    await expectLater(
      fixture.openItemChat(),
      throwsA(isA<ChatRemoteException>()),
    );
    expect(fixture.messages, hasLength(1));
  });

  test(
    'failed insertion can be retried without retaining a pending send',
    () async {
      final fixture = _ChatFixture();
      addTearDown(fixture.client.dispose);
      fixture.failNextInsert = true;
      await expectLater(
        fixture.openItemChat(),
        throwsA(isA<ChatRemoteException>()),
      );
      await fixture.openItemChat();
      await fixture.openItemChat();
      expect(fixture.messages, hasLength(1));
    },
  );

  test('ordinary repeated text messages are still sent', () async {
    final fixture = _ChatFixture();
    addTearDown(fixture.client.dispose);
    final source = ChatRemoteDataSource(client: fixture.authenticated);
    await source.sendMessage(conversationId: 'room', message: 'สวัสดีครับ');
    await source.sendMessage(conversationId: 'room', message: 'สวัสดีครับ');
    expect(fixture.messages, hasLength(2));
  });
}
