import '../../domain/entities/chat_message.dart';

class ChatResponseModel {
  const ChatResponseModel({
    required this.answer,
    required this.recommendedItems,
    this.suggestedReplies = const [],
    this.questions = const [],
  });

  factory ChatResponseModel.fromJson(Map<String, dynamic> json) {
    final answer = json['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const FormatException('Chat response must contain an answer');
    }

    final rawItems = json['recommended_items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => RecommendedItemModel.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
        : const <RecommendedItemModel>[];

    final rawReplies = json['suggested_replies'];
    final replies = rawReplies is List
        ? rawReplies
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final rawQuestions = json['questions'];
    final questions = rawQuestions is List
        ? rawQuestions
              .whereType<Map>()
              .map(
                (q) => ClarificationQuestionModel.fromJson(
                  q.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
        : const <ClarificationQuestionModel>[];

    return ChatResponseModel(
      answer: answer.trim(),
      recommendedItems: items,
      suggestedReplies: replies,
      questions: questions,
    );
  }

  final String answer;
  final List<RecommendedItemModel> recommendedItems;
  final List<String> suggestedReplies;
  final List<ClarificationQuestionModel> questions;

  ChatResponse toEntity() {
    return ChatResponse(
      answer: answer,
      recommendedItems: recommendedItems
          .map((item) => item.toEntity())
          .toList(growable: false),
      suggestedReplies: suggestedReplies,
      questions: questions
          .map((question) => question.toEntity())
          .toList(growable: false),
    );
  }
}

class ClarificationQuestionModel {
  const ClarificationQuestionModel({
    required this.id,
    required this.title,
    required this.options,
    this.step = 1,
    this.totalSteps = 2,
    this.selectedOption,
  });

  factory ClarificationQuestionModel.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = rawOptions is List
        ? rawOptions
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final rawStep = json['step'];
    final step = rawStep is num ? rawStep.toInt() : (int.tryParse('$rawStep') ?? 1);

    final rawTotal = json['total_steps'];
    final totalSteps = rawTotal is num ? rawTotal.toInt() : (int.tryParse('$rawTotal') ?? 2);

    return ClarificationQuestionModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      options: options,
      step: step,
      totalSteps: totalSteps,
      selectedOption: json['selected_option']?.toString(),
    );
  }

  final String id;
  final String title;
  final List<String> options;
  final int step;
  final int totalSteps;
  final String? selectedOption;

  ClarificationQuestion toEntity() {
    return ClarificationQuestion(
      id: id,
      title: title,
      options: options,
      step: step,
      totalSteps: totalSteps,
      selectedOption: selectedOption,
    );
  }
}

class RecommendedItemModel {
  const RecommendedItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.unit,
    required this.imageUrl,
    required this.status,
    required this.category,
    required this.description,
  });

  factory RecommendedItemModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawPrice = json['price'];

    return RecommendedItemModel(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId'),
      name: _stringValue(json['item_name'], fallback: 'อุปกรณ์แนะนำ'),
      price: rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse('$rawPrice'),
      unit: _stringValue(json['unit'], fallback: 'วัน'),
      imageUrl: _stringValue(json['image_url']),
      status: _nullableString(json['status']),
      category: _nullableString(json['category']),
      description: _nullableString(json['description']),
    );
  }

  final int? id;
  final String name;
  final double? price;
  final String unit;
  final String imageUrl;
  final String? status;
  final String? category;
  final String? description;

  RecommendedItem toEntity() {
    return RecommendedItem(
      id: id,
      name: name,
      price: price,
      unit: unit,
      imageUrl: imageUrl,
      status: status,
      category: category,
      description: description,
    );
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    final stringValue = value is String ? value.trim() : '';
    return stringValue.isEmpty ? fallback : stringValue;
  }

  static String? _nullableString(Object? value) {
    final stringValue = _stringValue(value);
    return stringValue.isEmpty ? null : stringValue;
  }
}
