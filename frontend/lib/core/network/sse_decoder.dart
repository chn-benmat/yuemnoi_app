import 'dart:async';
import 'dart:convert';

import 'package:eventflux/eventflux.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ให้ EventFlux จัดการขอบเขต event โดยคง HTTP, headers และการยกเลิกไว้ที่ ApiClient
Stream<EventFluxData> decodeSse(Stream<String> lines) {
  final client = EventFlux.spawn();
  final adapter = _LineStreamAdapter(lines);
  StreamSubscription<EventFluxData>? subscription;
  late final StreamController<EventFluxData> output;
  output = StreamController<EventFluxData>(
    onListen: () {
      client.connect(
        EventFluxConnectionType.post,
        'https://sse.internal/decoded-stream',
        httpClient: adapter,
        webConfig: kIsWeb ? WebConfig() : null,
        onSuccessCallback: (response) {
          subscription = response?.stream?.listen(
            output.add,
            onError: output.addError,
            onDone: () => unawaited(output.close()),
          );
        },
        onError: (error) {
          if (output.isClosed) return;
          output.addError(
            error.originalError ?? error,
            error.stackTrace ?? StackTrace.current,
          );
          unawaited(output.close());
        },
        // การ reconnect POST อาจส่งคำถามเดิมซ้ำ จึงให้ผู้ใช้เป็นผู้ลองใหม่
        autoReconnect: false,
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      await adapter.cancel();
      await subscription?.cancel();
      await client.disconnect();
    },
  );
  return output.stream;
}

class _LineStreamAdapter implements HttpClientAdapter {
  _LineStreamAdapter(this.lines);
  final Stream<String> lines;
  StreamSubscription<List<int>>? _subscription;
  bool _cancelled = false;

  Future<void> cancel() async {
    _cancelled = true;
    await _subscription?.cancel();
  }

  Stream<List<int>> _bytes() => Stream.multi((output) {
    // EventFlux อาจได้รับ response หลังผู้ใช้ยกเลิกแล้ว จึงไม่เริ่ม HTTP ต้นทางในกรณีนั้น
    if (_cancelled) {
      output.closeSync();
      return;
    }
    final subscription = lines
        .transform(
          StreamTransformer<String, List<int>>.fromHandlers(
            handleData: (line, sink) =>
                sink.add(utf8.encode(line.endsWith('\n') ? line : '$line\n')),
            handleDone: (sink) {
              // ปิด event สุดท้ายตาม contract เดิม โดยไม่เพิ่ม async generator ที่หน่วง cancellation
              sink.add(const [10]);
              sink.close();
            },
          ),
        )
        .listen(
          output.addSync,
          onError: output.addErrorSync,
          onDone: output.closeSync,
        );
    _subscription = subscription;
    output.onCancel = subscription.cancel;
    output.onPause = subscription.pause;
    output.onResume = subscription.resume;
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        _bytes(),
        200,
        headers: const {'content-type': 'text/event-stream'},
      );
}
