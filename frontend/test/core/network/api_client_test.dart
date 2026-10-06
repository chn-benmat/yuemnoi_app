import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';

void main() {
  test(
    'HTTP 503 before SSE preserves the safe code instead of waiting for done',
    () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://example.test',
          validateStatus: (status) => status != null && status < 600,
        ),
      )..httpClientAdapter = _RateLimitedAdapter();
      final client = DioApiClient(dio: dio, appSecret: 'test');
      addTearDown(client.close);
      await expectLater(
        await client.postStream('/api/chat-ai/stream'),
        emitsError(
          isA<ApiClientException>()
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.errorCode, 'safe code', 'providers_rate_limited')
              .having((e) => e.retryAfterSeconds, 'retry delay', 60),
        ),
      );
    },
  );
  test('non-stream HTTP quota response preserves Retry-After', () async {
    final client = DioApiClient(
      dio: Dio(
        BaseOptions(
          baseUrl: 'https://example.test',
          validateStatus: (status) => status != null && status < 600,
        ),
      )..httpClientAdapter = _RateLimitedAdapter(),
      appSecret: '',
    );
    addTearDown(client.close);
    final result = await client.post('/api/chat-ai');
    expect(result.statusCode, 503);
    expect(result.retryAfterSeconds, 60);
  });
  test(
    'cancelling SSE interrupts HTTP while headers are still pending',
    () async {
      final adapter = _PendingHeadersAdapter();
      final client = DioApiClient(
        dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
          ..httpClientAdapter = adapter,
        appSecret: '',
      );
      addTearDown(client.close);
      final stream = await client.postStream('/stream');
      final subscription = stream.listen((_) => fail('No response is ready'));
      await adapter.started.future;
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await adapter.cancelled.future.timeout(const Duration(seconds: 1));
      adapter.response.complete(ResponseBody.fromString('', 200));
    },
  );
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

class _PendingHeadersAdapter extends _RecordingAdapter {
  final started = Completer<void>();
  final cancelled = Completer<void>();
  final response = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    cancelFuture!.then((_) => cancelled.complete());
    started.complete();
    return response.future;
  }
}

class _RateLimitedAdapter extends _RecordingAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error_code":"providers_rate_limited"}',
    503,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      'retry-after': ['60'],
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
