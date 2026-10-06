import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/data/models/chat_understanding_model.dart';
import 'package:frontend/features/chatbot/data/models/chat_response_model.dart';
import 'package:frontend/features/chatbot/presentation/widgets/chat_response_label.dart';

void main() {
  const base = {
    'request_scope': 'specific',
    'information_sufficient': true,
    'next_action': 'answer',
    'response_flow': 'equipment',
  };

  test('response labels use actual kind with legacy compatibility', () {
    for (final entry in {
      'item_details': 'ข้อมูลสินค้า',
      'comparison': 'ผลการเปรียบเทียบ',
      'conversation': 'คำตอบ',
      'information': 'คำตอบ',
      'technical': 'ข้อมูลทางเทคนิค',
      'overview': 'รายการอุปกรณ์',
      'recommendation': 'สรุปคำแนะนำ',
    }.entries) {
      final value = ChatUnderstandingModel.fromJson({
        ...base,
        'response_kind': entry.key,
        'search_query': '',
      });
      expect(chatResponseLabel(value?.responseKind), entry.value);
    }
    expect(ChatUnderstandingModel.fromJson(base)?.responseKind, isNull);
    expect(chatResponseLabel(null), 'สรุปคำแนะนำ');
    expect(
      chatResponseLabel('item_details', hasQuestions: true),
      'สอบถามข้อมูลเพิ่มเติม',
    );
    expect(
      () => ChatUnderstandingModel.fromJson({
        ...base,
        'response_kind': 'unsupported',
      }),
      throwsFormatException,
    );
  });

  test('canonical display preserves raw price unit and status', () {
    final value = RecommendedItemModel.fromJson({
      'id': '1',
      'name': 'fixture',
      'price': 650.5,
      'unit': 'daily',
      'status': 'available',
      'price_display': '650.5 บาทต่อวัน',
      'unit_display': 'วัน',
      'status_display': 'มีในคลัง',
    }).toEntity();
    expect(value.price, 650.5);
    expect(value.unit, 'daily');
    expect(value.status, 'available');
    expect(value.priceDisplay, '650.5 บาทต่อวัน');
    expect(value.unitDisplay, 'วัน');
    expect(value.statusDisplay, 'มีในคลัง');
  });
}
