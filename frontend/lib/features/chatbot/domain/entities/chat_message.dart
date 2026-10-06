import 'package:equatable/equatable.dart';
import 'chat_context.dart';
import 'chat_understanding.dart';
export 'chat_context.dart';
export 'chat_understanding.dart';

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
    this.priceDisplay,
    this.unitDisplay,
    this.statusDisplay,
  });

  final int? id;
  final String name;
  final double? price;
  final String unit;
  final String imageUrl;
  final String? status;
  final String? category;
  final String? description;
  final String? priceDisplay;
  final String? unitDisplay;
  final String? statusDisplay;

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
    priceDisplay,
    unitDisplay,
    statusDisplay,
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
    this.selectedOptionId,
    this.dimension = '',
    this.choices = const [],
    this.branchOptions,
    this.branchTitles,
  });

  final String id;
  final String title;
  final List<String> options;
  final int step;
  final int totalSteps;
  final String? selectedOption;
  final String? selectedOptionId;
  final String dimension;
  final List<QuestionChoice> choices;
  final Map<String, List<String>>? branchOptions;
  final Map<String, String>? branchTitles;

  ClarificationQuestion copyWith({
    String? id,
    String? title,
    List<String>? options,
    int? step,
    int? totalSteps,
    String? selectedOption,
    String? selectedOptionId,
    String? dimension,
    List<QuestionChoice>? choices,
    Map<String, List<String>>? branchOptions,
    Map<String, String>? branchTitles,
  }) {
    return ClarificationQuestion(
      id: id ?? this.id,
      title: title ?? this.title,
      options: options ?? this.options,
      step: step ?? this.step,
      totalSteps: totalSteps ?? this.totalSteps,
      selectedOption: selectedOption ?? this.selectedOption,
      selectedOptionId: selectedOptionId ?? this.selectedOptionId,
      dimension: dimension ?? this.dimension,
      choices: choices ?? this.choices,
      branchOptions: branchOptions ?? this.branchOptions,
      branchTitles: branchTitles ?? this.branchTitles,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    options,
    step,
    totalSteps,
    selectedOption,
    selectedOptionId,
    dimension,
    choices,
    branchOptions,
    branchTitles,
  ];
}

class SearchSource extends Equatable {
  const SearchSource({
    required this.title,
    required this.url,
    required this.domain,
    this.snippet,
  });

  final String title;
  final String url;
  final String domain;
  final String? snippet;

  @override
  List<Object?> get props => [title, url, domain, snippet];
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
    this.understanding,
    this.responseDuration,
    this.isStreaming = false,
    this.isVisibleInChat = true,
    this.thought,
    this.searchSources = const [],
    this.searchQuery,
    this.context,
    this.references = const [],
    this.statusMessage,
    this.activities = const [],
    this.createdAt,
  });

  final String id;
  final ChatMessageRole role;
  final String content;
  final String? userQuery;
  final List<RecommendedItem> recommendedItems;
  final List<String> suggestedReplies;
  final List<ClarificationQuestion> questions;
  final ChatUnderstanding? understanding;
  final Duration? responseDuration;
  final bool isStreaming;
  final bool isVisibleInChat;
  final String? thought;
  final List<SearchSource> searchSources;
  final String? searchQuery;
  final ChatSessionContext? context;
  final List<EvidenceReference> references;
  final String? statusMessage;
  final List<String> activities;
  final DateTime? createdAt;

  ChatMessage copyWith({
    String? id,
    ChatMessageRole? role,
    String? content,
    String? userQuery,
    List<RecommendedItem>? recommendedItems,
    List<String>? suggestedReplies,
    List<ClarificationQuestion>? questions,
    ChatUnderstanding? understanding,
    Duration? responseDuration,
    bool? isStreaming,
    bool? isVisibleInChat,
    String? thought,
    List<SearchSource>? searchSources,
    String? searchQuery,
    ChatSessionContext? context,
    List<EvidenceReference>? references,
    String? statusMessage,
    List<String>? activities,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      userQuery: userQuery ?? this.userQuery,
      recommendedItems: recommendedItems ?? this.recommendedItems,
      suggestedReplies: suggestedReplies ?? this.suggestedReplies,
      questions: questions ?? this.questions,
      understanding: understanding ?? this.understanding,
      responseDuration: responseDuration ?? this.responseDuration,
      isStreaming: isStreaming ?? this.isStreaming,
      isVisibleInChat: isVisibleInChat ?? this.isVisibleInChat,
      thought: thought ?? this.thought,
      searchSources: searchSources ?? this.searchSources,
      searchQuery: searchQuery ?? this.searchQuery,
      context: context ?? this.context,
      references: references ?? this.references,
      statusMessage: statusMessage ?? this.statusMessage,
      activities: activities ?? this.activities,
      createdAt: createdAt ?? this.createdAt,
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
    understanding,
    responseDuration,
    isStreaming,
    isVisibleInChat,
    thought,
    searchSources,
    searchQuery,
    context,
    references,
    statusMessage,
    activities,
    createdAt,
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
    this.understanding,
  });

  final String mode;
  final List<RecommendedItem> recommendedItems;
  final List<ClarificationQuestion> questions;
  final ChatUnderstanding? understanding;

  @override
  List<Object?> get props => [mode, recommendedItems, questions, understanding];
}

class ChatDeltaEvent extends ChatStreamEvent {
  const ChatDeltaEvent({required this.text});

  final String text;

  @override
  List<Object?> get props => [text];
}

// คำตอบทั้งชุดผ่านการตรวจและส่งมาถึงแอปแล้ว ก่อนเริ่มแสดงตัวอักษร
class ChatReadyEvent extends ChatStreamEvent {
  const ChatReadyEvent({required this.response});
  final ChatResponse response;
  @override
  List<Object?> get props => [response];
}

class ChatDoneEvent extends ChatStreamEvent {
  const ChatDoneEvent({
    this.answer,
    this.suggestedReplies = const [],
    this.recommendedItems = const [],
    this.questions = const [],
    this.understanding,
    this.thought,
    this.searchSources = const [],
    this.searchQuery,
    this.context,
    this.references = const [],
    this.activities = const [],
  });

  final String? answer;
  final List<String> suggestedReplies;
  final List<RecommendedItem> recommendedItems;
  final List<ClarificationQuestion> questions;
  final ChatUnderstanding? understanding;
  final String? thought;
  final List<SearchSource> searchSources;
  final String? searchQuery;
  final ChatSessionContext? context;
  final List<EvidenceReference> references;
  final List<String> activities;

  @override
  List<Object?> get props => [
    answer,
    suggestedReplies,
    recommendedItems,
    questions,
    understanding,
    thought,
    searchSources,
    searchQuery,
    context,
    references,
    activities,
  ];
}

class ChatResponse extends Equatable {
  const ChatResponse({
    required this.answer,
    this.recommendedItems = const [],
    this.suggestedReplies = const [],
    this.questions = const [],
    this.understanding,
    this.thought,
    this.searchSources = const [],
    this.searchQuery,
    this.context,
    this.references = const [],
  });

  final String answer;
  final List<RecommendedItem> recommendedItems;
  final List<String> suggestedReplies;
  final List<ClarificationQuestion> questions;
  final ChatUnderstanding? understanding;
  final String? thought;
  final List<SearchSource> searchSources;
  final String? searchQuery;
  final ChatSessionContext? context;
  final List<EvidenceReference> references;

  @override
  List<Object?> get props => [
    answer,
    recommendedItems,
    suggestedReplies,
    questions,
    understanding,
    thought,
    searchSources,
    searchQuery,
    context,
    references,
  ];
}
