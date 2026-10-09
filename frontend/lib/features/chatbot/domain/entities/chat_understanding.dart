import 'package:equatable/equatable.dart';

// ผลที่บริการวิเคราะห์ไว้แล้ว ไม่ตีความข้อความซ้ำในแอป
class ChatUnderstanding extends Equatable {
  const ChatUnderstanding({
    required this.requestScope,
    required this.informationSufficient,
    required this.nextAction,
    required this.responseFlow,
    this.responseKind,
  });

  final String requestScope;
  final bool informationSufficient;
  final String nextAction;
  final String responseFlow;
  final String? responseKind;

  @override
  List<Object?> get props => [
    requestScope,
    informationSufficient,
    nextAction,
    responseFlow,
    responseKind,
  ];
}
