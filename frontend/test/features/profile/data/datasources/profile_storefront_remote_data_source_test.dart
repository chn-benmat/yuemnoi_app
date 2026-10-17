import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/datasources/profile_storefront_remote_data_source.dart';
import 'package:frontend/features/profile/data/repositories/profile_storefront_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'public queries exclude moderated rows and paginate complete review counts',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.uri);
        final query = request.uri.queryParameters;
        Object response;
        if (request.uri.path.endsWith('public_profile_v')) {
          response = {'display_name': 'Public Owner', 'is_verified': true};
        } else if (request.uri.path.endsWith('item_tb')) {
          expect(query['user_id'], 'eq.owner');
          expect(query['moderation_hidden'], 'eq.false');
          response = [
            {
              'id': 1,
              'item_name': 'Camera',
              'price': 120,
              'type': 'รายชั่วโมง',
              'status': 'rented',
            },
          ];
        } else {
          expect(query['moderation_hidden'], 'eq.false');
          expect(query['item_id'], 'in.(1)');
          expect(query['order'], startsWith('id.asc'));
          final offset = int.parse(query['offset'] ?? '0');
          response = List.generate(
            offset == 0 ? 500 : 1,
            (index) => {
              'id': offset + index,
              'item_id': 1,
              'rating': offset == 0 ? '4' : '5',
            },
          );
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
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
      final repository = ProfileStorefrontRepositoryImpl(
        dataSource: ProfileStorefrontRemoteDataSource(client: client),
      );
      final identity = await repository.getIdentity('owner');
      expect(identity.isVerified, isTrue);
      final items = await repository.getItems('owner');
      expect(items.single.status, 'rented');
      expect(items.single.rentalType, 'รายชั่วโมง');
      final reviews = await repository.getReviews([1]);
      expect(reviews.length, 501);
      expect(reviews.last.rating, 5);
      expect(requests.where((uri) => uri.path.endsWith('review_tb')).length, 2);
      expect(requests.any((uri) => uri.path.endsWith('profile_tb')), isFalse);
    },
  );
}
