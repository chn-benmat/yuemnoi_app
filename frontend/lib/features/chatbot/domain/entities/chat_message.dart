import 'package:equatable/equatable.dart';

enum ChatMessageRole { user, assistant }

extension ChatMessageRoleValue on ChatMessageRole {
  String get apiValue => switch (this) {
    ChatMessageRole.user => 'user',
    ChatMessageRole.assistant => 'assistant',
  };
}

class RecommendedItem extends Equatable {
  const RecommendedItem({
    required this.id,
    required this.name,
    required this.price,
    required this.unit,
    required this.imageUrl,
    required this.status,
    required this.category,
    required this.description,
  });

  final int? id;
  final String name;
  final double? price;
  final String unit;
  final String imageUrl;
  final String? status;
  final String? category;
  final String? description;

  @override
  List<Object?> get props => [
    id,
    name,
    price,
    unit,
    imageUrl,
    status,
    category,
    description,
  ];
}

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.role,
    required this.content,
    this.recommendedItems = const [],
  });

  final ChatMessageRole role;
  final String content;
  final List<RecommendedItem> recommendedItems;

  @override
  List<Object?> get props => [role, content, recommendedItems];
}

class ChatResponse extends Equatable {
  const ChatResponse({required this.answer, this.recommendedItems = const []});

  final String answer;
  final List<RecommendedItem> recommendedItems;

  @override
  List<Object?> get props => [answer, recommendedItems];
}
