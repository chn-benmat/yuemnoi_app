import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/rental_return/data/datasources/rental_return_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'return image uses the item owner and item ID from the booking',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'return-image-test',
      );
      final photo = File('${directory.path}/photo.jpg');
      await photo.writeAsBytes([1, 2, 3]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? uploadedPath;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/rest/v1/booking_tb') {
          expect(request.uri.queryParameters['id'], 'eq.73');
          request.response.write('{"item_id":42}');
        } else if (request.uri.path == '/rest/v1/item_tb') {
          expect(request.uri.queryParameters['id'], 'eq.42');
          request.response.write('{"user_id":"item-owner"}');
        } else {
          uploadedPath = request.uri.path;
          expect(request.headers.contentType?.mimeType, 'multipart/form-data');
          expect(request.headers.value('x-upsert'), 'false');
          final body = await utf8.decoder.bind(request).join();
          expect(body.toLowerCase(), contains('content-type: image/jpeg'));
          request.response.write(jsonEncode({'Key': uploadedPath}));
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
      );
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
        await directory.delete(recursive: true);
      });

      final result = await RentalReturnRemoteDataSource(
        client: client,
      ).uploadPhoto(rentalId: 73, photoPath: photo.path, angleKey: 'angle_1');

      expect(
        uploadedPath,
        startsWith(
          '/storage/v1/object/item_bk/item-owner/42/return_73_angle_1_',
        ),
      );
      expect(
        result,
        contains(
          '/storage/v1/object/public/item_bk/item-owner/42/return_73_angle_1_',
        ),
      );
    },
  );

  test(
    'uninitialized client preserves the existing local session path',
    () async {
      final source = RentalReturnRemoteDataSource();

      final session = await source.getSession(73);

      expect(session.rentalId, 73);
    },
  );

  test('completion uses the injected Supabase client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final capturedRequest = Completer<Map<String, dynamic>>();
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      capturedRequest.complete({
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'body': jsonDecode(body),
      });
      request.response.statusCode = HttpStatus.noContent;
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
    final source = RentalReturnRemoteDataSource(client: client);

    await source.markCompleted(73);
    final request = await capturedRequest.future.timeout(
      const Duration(seconds: 5),
    );

    expect(request['method'], 'PATCH');
    expect(request['path'], '/rest/v1/booking_tb');
    expect(request['query'], {'id': 'eq.73'});
    expect(request['body']['status'], 'คืนของสำเร็จ');
  });
}
