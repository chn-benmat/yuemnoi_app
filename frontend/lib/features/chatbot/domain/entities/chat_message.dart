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

class ClarificationQuestion extends Equatable {
  const ClarificationQuestion({
    required this.id,
    required this.title,
    required this.options,
    this.step = 1,
    this.totalSteps = 2,
    this.selectedOption,
  });

  final String id;
  final String title;
  final List<String> options;
  final int step;
  final int totalSteps;
  final String? selectedOption;

  ClarificationQuestion copyWith({
    String? id,
    String? title,
    List<String>? options,
    int? step,
    int? totalSteps,
    String? selectedOption,
  }) {
    return ClarificationQuestion(
      id: id ?? this.id,
      title: title ?? this.title,
      options: options ?? this.options,
      step: step ?? this.step,
      totalSteps: totalSteps ?? this.totalSteps,
      selectedOption: selectedOption ?? this.selectedOption,
    );
  }

  @override
  List<Object?> get props => [id, title, options, step, totalSteps, selectedOption];
}

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.role,
    required this.content,
    this.id = '',
    this.userQuery,
    this.recommendedItems = const [],
    this.suggestedReplies = const [],
    this.questions = const [],
    this.responseDuration,
    this.isStreaming = false,
    this.isLiked,
    this.feedbackReason,
    this.feedbackComment,
  });

  final String id;
  final ChatMessageRole role;
  final String content;
  final String? userQuery;
  final List<RecommendedItem> recommendedItems;
  final List<String> suggestedReplies;
  final List<ClarificationQuestion> questions;
  final Duration? responseDuration;
  final bool isStreaming;
  final bool? isLiked;
  final String? feedbackReason;
  final String? feedbackComment;

  ChatMessage copyWith({
    String? id,
    ChatMessageRole? role,
    String? content,
    String? userQuery,
    List<RecommendedItem>? recommendedItems,
    List<String>? suggestedReplies,
    List<ClarificationQuestion>? questions,
    Duration? responseDuration,
    bool? isStreaming,
    bool? isLiked,
    String? feedbackReason,
    String? feedbackComment,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      userQuery: userQuery ?? this.userQuery,
      recommendedItems: recommendedItems ?? this.recommendedItems,
      suggestedReplies: suggestedReplies ?? this.suggestedReplies,
      questions: questions ?? this.questions,
      responseDuration: responseDuration ?? this.responseDuration,
      isStreaming: isStreaming ?? this.isStreaming,
      isLiked: isLiked ?? this.isLiked,
      feedbackReason: feedbackReason ?? this.feedbackReason,
      feedbackComment: feedbackComment ?? this.feedbackComment,
    );
  }

  @override
  List<Object?> get props => [
    id,
    role,
    content,
    userQuery,
    recommendedItems,
    suggestedReplies,
    questions,
    responseDuration,
    isStreaming,
    isLiked,
    feedbackReason,
    feedbackComment,
  ];
}

sealed class ChatStreamEvent extends Equatable {
  const ChatStreamEvent();
}

class ChatStatusEvent extends ChatStreamEvent {
  const ChatStatusEvent({required this.step, required this.message});

  final String step;
  final String message;

  @override
  List<Object?> get props => [step, message];
}

class ChatMetadataEvent extends ChatStreamEvent {
  const ChatMetadataEvent({
    required this.mode,
    this.recommendedItems = const [],
    this.questions = const [],
  });

  final String mode;
  final List<RecommendedItem> recommendedItems;
  final List<ClarificationQuestion> questions;

  @override
  List<Object?> get props => [mode, recommendedItems, questions];
}

class ChatDeltaEvent extends ChatStreamEvent {
  const ChatDeltaEvent({required this.text});

  final String text;

  @override
  List<Object?> get props => [text];
}

class ChatDoneEvent extends ChatStreamEvent {
  const ChatDoneEvent({
    this.suggestedReplies = const [],
    this.recommendedItems = const [],
    this.questions = const [],
  });

  final List<String> suggestedReplies;
  final List<RecommendedItem> recommendedItems;
  final List<ClarificationQuestion> questions;

  @override
  List<Object?> get props => [suggestedReplies, recommendedItems, questions];
}

class ChatResponse extends Equatable {
  const ChatResponse({
    required this.answer,
    this.recommendedItems = const [],
    this.suggestedReplies = const [],
    this.questions = const [],
  });

  final String answer;
  final List<RecommendedItem> recommendedItems;
  final List<String> suggestedReplies;
  final List<ClarificationQuestion> questions;

  @override
  List<Object?> get props => [
    answer,
    recommendedItems,
    suggestedReplies,
    questions,
  ];
}
