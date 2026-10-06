import '../../domain/entities/chat_understanding.dart';

class ChatUnderstandingModel {
  static ChatUnderstanding? fromJson(Map<String, dynamic> json) {
    final scope = json['request_scope'];
    final sufficient = json['information_sufficient'];
    final action = json['next_action'];
    final flow = json['response_flow'];
    final kind = json['response_kind'];
    if (scope == null && sufficient == null && action == null && flow == null) {
      return null;
    }
    // ตรวจค่าตามสัญญาเท่านั้น ไม่มีการจับคำจากประโยคผู้ใช้
    if (!const ['broad', 'specific', 'not_applicable'].contains(scope) ||
        sufficient is! bool ||
        !const ['answer', 'clarify'].contains(action) ||
        !const ['general', 'equipment', 'technical'].contains(flow) ||
        (kind != null &&
            !const [
              'clarification',
              'conversation',
              'information',
              'overview',
              'recommendation',
              'item_details',
              'comparison',
              'technical',
              'app_information',
            ].contains(kind))) {
      throw const FormatException('Invalid chat understanding');
    }
    return ChatUnderstanding(
      requestScope: scope as String,
      informationSufficient: sufficient,
      nextAction: action as String,
      responseFlow: flow as String,
      responseKind: kind as String?,
    );
  }
}
