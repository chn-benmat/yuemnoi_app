import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';

void main() {
  test(
    'DioApiClient attaches the configured app secret to every request',
    () async {
      final adapter = _RecordingAdapter();
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://example.test',
          validateStatus: (status) => status != null && status < 600,
        ),
      )..httpClientAdapter = adapter;
      final client = DioApiClient(dio: dio, appSecret: 'test-app-secret');

      await client.get('/items', headers: const {'X-App-Secret': 'incorrect'});

      expect(adapter.lastRequest?.headers['X-App-Secret'], 'test-app-secret');
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      '{}',
      HttpStatus.ok,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

abstract final class HttpStatus {
  static const int ok = 200;
}
