// วัดด้วยนาฬิกาต่อเนื่อง ไม่อิงเวลาระบบและไม่บันทึกเนื้อหาผู้ใช้
class ChatTurnTiming {
  ChatTurnTiming({this.origin = 'flutter_interaction'}) {
    _clock.start();
  }

  final String origin;
  final Stopwatch _clock = Stopwatch();
  Duration? firstText;
  Duration? responseReady;
  Duration? transportComplete;
  bool _finished = false;

  Duration get elapsed => _clock.elapsed;
  void markFirstText() => firstText ??= elapsed;
  void markResponseReady() => responseReady ??= elapsed;
  void markTransportComplete() => transportComplete ??= elapsed;

  ChatTimingMeasurement? finish({
    required String turnId,
    required String outcome,
    String? responseFlow,
    bool rendered = false,
  }) {
    if (_finished) return null;
    _finished = true;
    _clock.stop();
    return ChatTimingMeasurement(
      turnId: turnId,
      origin: origin,
      outcome: outcome,
      responseFlow: responseFlow,
      firstText: firstText,
      responseReady: responseReady,
      transportComplete: transportComplete,
      completeRender: rendered ? elapsed : null,
      elapsed: elapsed,
    );
  }
}

class ChatTimingMeasurement {
  const ChatTimingMeasurement({
    required this.turnId,
    required this.origin,
    required this.outcome,
    required this.elapsed,
    this.responseFlow,
    this.firstText,
    this.responseReady,
    this.transportComplete,
    this.completeRender,
  });

  final String turnId;
  final String origin;
  final String outcome;
  final String? responseFlow;
  final Duration elapsed;
  final Duration? firstText;
  final Duration? responseReady;
  final Duration? transportComplete;
  final Duration? completeRender;

  Map<String, Object?> toJson() => {
    'turn_id': turnId,
    'origin': origin,
    'outcome': outcome,
    'response_flow': responseFlow,
    'first_text_microseconds': firstText?.inMicroseconds,
    'response_ready_microseconds': responseReady?.inMicroseconds,
    'transport_complete_microseconds': transportComplete?.inMicroseconds,
    'complete_render_microseconds': completeRender?.inMicroseconds,
    'elapsed_microseconds': elapsed.inMicroseconds,
    'render_boundary': 'post_frame_text_questions_card_data',
    'image_download_included': false,
  };
}
