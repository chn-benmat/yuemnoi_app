import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/data/models/chat_response_model.dart';
import 'package:frontend/features/chatbot/data/models/chat_context_model.dart';
import 'package:frontend/features/chatbot/domain/entities/chat_message.dart';

void main() {
  test('response keeps filtering, trimming and answer validation', () {
    final response = ChatResponseModel.fromJson({
      'answer': ' คำตอบ ',
      'recommended_items': [
        null,
        'ignored',
        {'id': '3'},
      ],
      'suggested_replies': [null, 1, ' ', ' ต่อไป '],
      'questions': [
        false,
        {
          'id': 4,
          'options': [' A ', '', null, 1],
          'step': '3',
        },
      ],
      'thought': ' คิด ',
      'search_query': ' ',
      'search_sources': [
        null,
        {'title': 12, 'url': 'url', 'domain': 'domain'},
      ],
    });
    expect(response.answer, 'คำตอบ');
    expect(response.recommendedItems.single.id, 3);
    expect(response.suggestedReplies, ['ต่อไป']);
    expect(response.questions.single.id, '4');
    expect(response.questions.single.options, ['A']);
    expect(response.questions.single.step, 3);
    expect(response.questions.single.totalSteps, 2);
    expect(response.thought, 'คิด');
    expect(response.searchQuery, isNull);
    expect(response.searchSources.single.title, '12');
    expect(response.context, isNull);
    expect(response.understanding, isNull);
    for (final answer in [null, '', ' ', 1]) {
      expect(
        () => ChatResponseModel.fromJson({'answer': answer}),
        throwsFormatException,
      );
    }
  });

  test('response keeps context, references and understanding contracts', () {
    final response = ChatResponseModel.fromJson({
      'answer': 'คำตอบ',
      'context': {'session_id': 'session', 'user_goal': 'goal'},
      'references': [
        {'id': 'r', 'kind': 'web', 'title': 'source', 'reference': 'url'},
      ],
      'request_scope': 'specific',
      'information_sufficient': true,
      'next_action': 'answer',
      'response_flow': 'equipment',
      'response_kind': 'recommendation',
    });
    expect(response.context!.sessionId, 'session');
    expect(response.references.single.id, 'r');
    expect(response.understanding!.responseKind, 'recommendation');
    expect(
      () => ChatResponseModel.fromJson({
        'answer': 'a',
        'request_scope': 'invalid',
      }),
      throwsFormatException,
    );
  });

  test(
    'adaptive choices retain dependency and exact billing values in return context',
    () {
      final payload = <String, dynamic>{
        'id': 'batch:budget',
        'title': 'งบค่าเช่า',
        'options': ['ไม่จำกัดงบ'],
        'branch_question_id': 'batch:kind',
        'branch_titles': {'music': 'งบค่าเช่าต่อวัน'},
        'branch_choices': {
          'music': [
            {
              'id': 'music:cap',
              'label': 'ไม่เกิน 350 บาทต่อวัน',
              'action_value': 'ไม่เกิน 350 บาทต่อวัน',
            },
          ],
        },
        'choices': [
          {
            'id': 'music:cap',
            'label': 'ไม่เกิน 350 บาทต่อวัน',
            'action_value': 'ไม่เกิน 350 บาทต่อวัน',
          },
        ],
      };
      final question = ClarificationQuestionModel.fromJson(payload).toEntity();
      expect(question.branchQuestionId, 'batch:kind');
      expect(question.branchChoices['music']!.single.id, 'music:cap');
      final encoded = ChatContextModel.toJson(
        ChatSessionContext(
          sessionId: 'session',
          userGoal: 'เลือกอุปกรณ์',
          questions: [question],
        ),
      );
      final returned = (encoded['questions'] as List).single as Map;
      expect(returned['branch_question_id'], payload['branch_question_id']);
      expect(returned['branch_choices'], payload['branch_choices']);
      expect(returned['branch_titles'], payload['branch_titles']);
    },
  );
  group('RecommendedItemModel.fromJson', () {
    test('preserves primary alias precedence and optional value filtering', () {
      final model = RecommendedItemModel.fromJson({
        'item_name': '',
        'name': 'Fallback name',
        'price': '350.5',
        'image_url': '',
        'image_urls': ['fallback image'],
        'unit': false,
        'status': ' ',
        'category': 1,
      });
      expect(model.name, 'อุปกรณ์แนะนำ');
      expect(model.price, 350.5);
      expect(model.imageUrl, '');
      expect(model.unit, 'วัน');
      expect(model.status, isNull);
      expect(model.category, isNull);
    });

    test(
      'parses Python AI service DTO format (name, image_urls list, type)',
      () {
        final json = {
          'id': 16,
          'name': 'เครื่องดูดฝุ่นไร้สาย Dyson V12 Detect Slim',
          'category': 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
          'price': 450.0,
          'type': 'วัน',
          'status': 'available',
          'image_urls': [
            'https://example.com/dyson1.jpg',
            'https://example.com/dyson2.jpg',
          ],
          'description': 'พลังดูดทรงพลังพร้อมเลเซอร์ตรวจจับฝุ่น',
        };

        final model = RecommendedItemModel.fromJson(json);

        expect(model.id, 16);
        expect(model.name, 'เครื่องดูดฝุ่นไร้สาย Dyson V12 Detect Slim');
        expect(model.price, 450.0);
        expect(model.unit, 'วัน');
        expect(model.imageUrl, 'https://example.com/dyson1.jpg');
        expect(model.category, 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน');
        expect(model.status, 'available');
      },
    );

    test(
      'parses Go backend format (name, item_name, image_url, price_unit)',
      () {
        final json = {
          'id': '17',
          'name': 'Xiaomi Smart Air Purifier 4 Pro',
          'item_name': 'Xiaomi Smart Air Purifier 4 Pro',
          'category': 'เครื่องใช้ไฟฟ้า',
          'price': 200,
          'price_unit': 'วัน',
          'status': 'available',
          'image_url': 'https://example.com/xiaomi.jpg',
          'description': 'กรองฝุ่น PM2.5',
        };

        final model = RecommendedItemModel.fromJson(json);

        expect(model.id, 17);
        expect(model.name, 'Xiaomi Smart Air Purifier 4 Pro');
        expect(model.price, 200.0);
        expect(model.unit, 'วัน');
        expect(model.imageUrl, 'https://example.com/xiaomi.jpg');
      },
    );

    test('handles fallback when fields are missing', () {
      final json = <String, dynamic>{'id': '99'};

      final model = RecommendedItemModel.fromJson(json);

      expect(model.id, 99);
      expect(model.name, 'อุปกรณ์แนะนำ');
      expect(model.price, null);
      expect(model.unit, 'วัน');
      expect(model.imageUrl, '');
    });
  });
}
