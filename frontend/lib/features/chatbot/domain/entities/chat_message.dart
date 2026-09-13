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
    this.branchOptions,
    this.branchTitles,
  });

  final String id;
  final String title;
  final List<String> options;
  final int step;
  final int totalSteps;
  final String? selectedOption;
  final Map<String, List<String>>? branchOptions;
  final Map<String, String>? branchTitles;

  ClarificationQuestion copyWith({
    String? id,
    String? title,
    List<String>? options,
    int? step,
    int? totalSteps,
    String? selectedOption,
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
    this.responseDuration,
    this.isStreaming = false,
    this.isVisibleInChat = true,
    this.thought,
    this.searchSources = const [],
    this.searchQuery,
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
  final Duration? responseDuration;
  final bool isStreaming;
  final bool isVisibleInChat;
  final String? thought;
  final List<SearchSource> searchSources;
  final String? searchQuery;
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
    Duration? responseDuration,
    bool? isStreaming,
    bool? isVisibleInChat,
    String? thought,
    List<SearchSource>? searchSources,
    String? searchQuery,
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
      responseDuration: responseDuration ?? this.responseDuration,
      isStreaming: isStreaming ?? this.isStreaming,
      isVisibleInChat: isVisibleInChat ?? this.isVisibleInChat,
      thought: thought ?? this.thought,
      searchSources: searchSources ?? this.searchSources,
      searchQuery: searchQuery ?? this.searchQuery,
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
    responseDuration,
    isStreaming,
    isVisibleInChat,
    thought,
    searchSources,
    searchQuery,
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
    this.answer,
    this.suggestedReplies = const [],
    this.recommendedItems = const [],
    this.questions = const [],
    this.thought,
    this.searchSources = const [],
    this.searchQuery,
    this.activities = const [],
  });

  final String? answer;
  final List<String> suggestedReplies;
  final List<RecommendedItem> recommendedItems;
  final List<ClarificationQuestion> questions;
  final String? thought;
  final List<SearchSource> searchSources;
  final String? searchQuery;
  final List<String> activities;

  @override
  List<Object?> get props => [
    answer,
    suggestedReplies,
    recommendedItems,
    questions,
    thought,
    searchSources,
    searchQuery,
    activities,
  ];
}

class ChatResponse extends Equatable {
  const ChatResponse({
    required this.answer,
    this.recommendedItems = const [],
    this.suggestedReplies = const [],
    this.questions = const [],
    this.thought,
    this.searchSources = const [],
    this.searchQuery,
  });

  final String answer;
  final List<RecommendedItem> recommendedItems;
  final List<String> suggestedReplies;
  final List<ClarificationQuestion> questions;
  final String? thought;
  final List<SearchSource> searchSources;
  final String? searchQuery;

  @override
  List<Object?> get props => [
    answer,
    recommendedItems,
    suggestedReplies,
    questions,
    thought,
    searchSources,
    searchQuery,
  ];
}
