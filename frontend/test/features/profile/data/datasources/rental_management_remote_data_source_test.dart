import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/datasources/rental_management_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'accepted offer is visible to renter and owner through actual database queries',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bookingQueries = <Uri>[];
      server.listen((request) async {
        Object data;
        if (request.uri.path.endsWith('booking_tb')) {
          bookingQueries.add(request.uri);
          data = [
            {
              'id': 25,
              'user_id': 'renter',
              'item_id': 7,
              'status': 'confirmed',
              'type': 'รายวัน',
              'start_at': '2026-10-18T02:00:00Z',
              'end_at': '2026-10-19T02:00:00Z',
              'total_price': 500,
              'pickup_location': 'Pickup',
            },
          ];
        } else if (request.uri.path.endsWith('item_tb')) {
          data = [
            {
              'id': 7,
              'user_id': 'owner',
              'item_name': 'Test camera',
              'type': 'รายวัน',
              'price': 500,
              'item_image_url': <String>[],
            },
          ];
        } else {
          data = [
            {'user_id': 'renter', 'display_name': 'Renter'},
            {'user_id': 'owner', 'display_name': 'Owner'},
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
      final source = RentalManagementRemoteDataSource(client: client);
      final renting = await source.getRentingBookings('renter');
      final lending = await source.getLendingBookings('owner');
      expect(renting.single.bookingId, 25);
      expect(lending.single.bookingId, 25);
      expect(renting.single.statusCode, 'confirmed');
      expect(lending.single.isOwner, isTrue);
      expect(bookingQueries.first.queryParameters['user_id'], 'eq.renter');
      expect(bookingQueries.last.queryParameters['item_id'], 'in.(7)');
    },
  );
}
