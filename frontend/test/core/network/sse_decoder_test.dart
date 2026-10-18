import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/sse_decoder.dart';

void main() {
  test(
    'cancelling before parsing starts does not start the HTTP source',
    () async {
      var started = false;
      final input = StreamController<String>(onListen: () => started = true);
      final result = decodeSse(input.stream).listen((_) {});
      await result.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(started, isFalse);
      unawaited(input.close());
    },
  );
  test(
    'assembles multiline data and preserves event boundaries and ids',
    () async {
      final events = await decodeSse(
        Stream.fromIterable([
          ': heartbeat',
          'event: delta',
          'id: first',
          'data: {',
          'data: "text":"สวัสดี"}',
          '',
          'event: done',
          'data: {}',
          '',
        ]),
      ).where((event) => event.data.isNotEmpty).toList();
      expect(events.map((event) => event.event), ['delta', 'done']);
      expect(events.first.id, 'first');
      expect(events.first.data, '{\n"text":"สวัสดี"}');
    },
  );

  test('preserves original API errors through the package adapter', () async {
    const failure = ApiClientException(ApiClientErrorType.connection);
    await expectLater(
      decodeSse(Stream.error(failure)),
      emitsError(same(failure)),
    );
  });

  test('cancelling decoding cancels the original HTTP line stream', () async {
    final cancelled = Completer<void>();
    final input = StreamController<String>(onCancel: cancelled.complete);
    final result = decodeSse(input.stream).listen((_) {});
    input.add(': heartbeat');
    await Future<void>.delayed(Duration.zero);
    await result.cancel();
    await cancelled.future.timeout(const Duration(seconds: 1));
    await input.close();
  });
}
