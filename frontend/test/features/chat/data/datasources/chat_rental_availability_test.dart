import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('reads rental availability only for the requested items', () async {
    final client = SupabaseClient(
      'https://chat.test',
      'test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/item_tb');
        expect(request.url.queryParameters, {
          'id': 'in.(1,2,3)',
          'select': 'id,is_rental_occupied,is_rental_queue_held',
        });
        return http.Response(
          '['
          '{"id":1,"is_rental_occupied":true,"is_rental_queue_held":false},'
          '{"id":2,"is_rental_occupied":false,"is_rental_queue_held":true},'
          '{"id":3,"is_rental_occupied":false,"is_rental_queue_held":false}'
          ']',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final source = ChatRemoteDataSource(client: client);
    expect(await source.getUnavailableRentalItemIds({1, 2, 3}), {1, 2});
  });
}
