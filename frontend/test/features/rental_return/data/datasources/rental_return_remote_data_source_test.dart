import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/rental_return/data/datasources/rental_return_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
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
