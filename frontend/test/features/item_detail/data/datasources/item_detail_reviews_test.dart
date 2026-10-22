import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/item_detail/data/datasources/item_detail_remote_data_source.dart';

class _Api extends Mock implements ApiClient {}

void main() {
  test(
    'API success paginates all item reviews and loads reviewer profiles',
    () async {
      final api = _Api();
      when(
        () => api.get('/api/items/7', headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => const ApiResponse(
          statusCode: 200,
          data: {
            'id': 7,
            'user_id': 'owner',
            'item_name': 'Camera',
            'price': 100,
          },
        ),
      );
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/review_tb')) {
            expect(request.url.queryParameters['item_id'], 'eq.7');
            expect(
              request.url.queryParameters['order'],
              startsWith('created_at.desc'),
            );
            final offset = int.parse(
              request.url.queryParameters['offset'] ?? '0',
            );
            expect(request.url.queryParameters['limit'], '100');
            return http.Response(
              jsonEncode(
                List.generate(
                  offset == 0 ? 100 : 1,
                  (index) => {
                    'id': offset + index,
                    'user_id': 'reviewer',
                    'rating': 5,
                    'description': 'Great camera',
                  },
                ),
              ),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          if (request.url.path.endsWith('/public_profile_v')) {
            return http.Response(
              jsonEncode([
                {'user_id': 'owner', 'display_name': 'Owner'},
                {'user_id': 'reviewer', 'display_name': 'Reviewer'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          fail('Unexpected request: ${request.url.path}');
        }),
      );
      addTearDown(client.dispose);
      final item = await ItemDetailRemoteDataSource(
        client: client,
        apiClient: api,
      ).fetchById(7);
      expect(item.reviews, hasLength(101));
      expect(item.reviews.first.description, 'Great camera');
      expect(item.reviews.first.reviewer.displayName, 'Reviewer');
    },
  );
}
