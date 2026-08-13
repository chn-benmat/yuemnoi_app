import '../../domain/entities/chat_message.dart';

class ChatResponseModel {
  const ChatResponseModel({
    required this.answer,
    required this.recommendedItems,
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

    return ChatResponseModel(answer: answer.trim(), recommendedItems: items);
  }

  final String answer;
  final List<RecommendedItemModel> recommendedItems;

  ChatResponse toEntity() {
    return ChatResponse(
      answer: answer,
      recommendedItems: recommendedItems
          .map((item) => item.toEntity())
          .toList(growable: false),
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
