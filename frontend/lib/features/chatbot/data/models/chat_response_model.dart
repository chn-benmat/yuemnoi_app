import '../../domain/entities/chat_message.dart';
import 'chat_context_model.dart';
import 'chat_understanding_model.dart';

class ChatResponseModel {
  const ChatResponseModel({
    required this.answer,
    required this.recommendedItems,
    this.suggestedReplies = const [],
    this.questions = const [],
    this.thought,
    this.searchSources = const [],
    this.searchQuery,
    this.context,
    this.references = const [],
    this.understanding,
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

    final rawThought = json['thought'];
    final thought = rawThought is String && rawThought.trim().isNotEmpty
        ? rawThought.trim()
        : null;

    final rawSearchQuery = json['search_query'];
    final searchQuery =
        rawSearchQuery is String && rawSearchQuery.trim().isNotEmpty
        ? rawSearchQuery.trim()
        : null;

    final rawSources = json['search_sources'];
    final searchSources = rawSources is List
        ? rawSources
              .whereType<Map>()
              .map(
                (s) => SearchSourceModel.fromJson(
                  s.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList(growable: false)
        : const <SearchSourceModel>[];

    return ChatResponseModel(
      answer: answer.trim(),
      recommendedItems: items,
      suggestedReplies: replies,
      questions: questions,
      thought: thought,
      searchSources: searchSources,
      searchQuery: searchQuery,
      context: ChatContextModel.fromJson(json['context']),
      references: ChatContextModel.references(json['references']),
      understanding: ChatUnderstandingModel.fromJson(json),
    );
  }

  final String answer;
  final List<RecommendedItemModel> recommendedItems;
  final List<String> suggestedReplies;
  final List<ClarificationQuestionModel> questions;
  final String? thought;
  final List<SearchSourceModel> searchSources;
  final String? searchQuery;
  final ChatSessionContext? context;
  final List<EvidenceReference> references;
  final ChatUnderstanding? understanding;

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
      thought: thought,
      searchSources: searchSources
          .map((source) => source.toEntity())
          .toList(growable: false),
      searchQuery: searchQuery,
      context: context,
      references: references,
      understanding: understanding,
    );
  }
}

class SearchSourceModel {
  const SearchSourceModel({
    required this.title,
    required this.url,
    required this.domain,
    this.snippet,
  });

  factory SearchSourceModel.fromJson(Map<String, dynamic> json) {
    return SearchSourceModel(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      snippet: json['snippet']?.toString(),
    );
  }

  final String title;
  final String url;
  final String domain;
  final String? snippet;

  SearchSource toEntity() {
    return SearchSource(
      title: title,
      url: url,
      domain: domain,
      snippet: snippet,
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
    this.selectedOptionId,
    this.dimension = '',
    this.choices = const [],
    this.branchOptions,
    this.branchTitles,
    this.branchQuestionId,
    this.branchChoices = const {},
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
    final step = rawStep is num
        ? rawStep.toInt()
        : (int.tryParse('$rawStep') ?? 1);

    final rawTotal = json['total_steps'];
    final totalSteps = rawTotal is num
        ? rawTotal.toInt()
        : (int.tryParse('$rawTotal') ?? 2);

    Map<String, List<String>>? branchOptions;
    if (json['branch_options'] is Map) {
      branchOptions = {};
      (json['branch_options'] as Map).forEach((k, v) {
        if (v is List) {
          branchOptions![k.toString()] = v.map((e) => e.toString()).toList();
        }
      });
    }

    Map<String, String>? branchTitles;
    if (json['branch_titles'] is Map) {
      branchTitles = {};
      (json['branch_titles'] as Map).forEach((k, v) {
        branchTitles![k.toString()] = v.toString();
      });
    }

    return ClarificationQuestionModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      options: options,
      step: step,
      totalSteps: totalSteps,
      selectedOption: json['selected_option']?.toString(),
      selectedOptionId: json['selected_option_id'] as String?,
      dimension: json['dimension'] as String? ?? '',
      choices: (json['choices'] as List? ?? [])
          .map(
            (c) => QuestionChoice(
              id: c['id'] as String,
              label: c['label'] as String,
              actionValue: c['action_value'] as String,
            ),
          )
          .toList(),
      branchOptions: branchOptions,
      branchTitles: branchTitles,
      branchQuestionId: json['branch_question_id'] as String?,
      branchChoices: {
        for (final entry in (json['branch_choices'] as Map? ?? {}).entries)
          entry.key as String: [
            for (final choice in entry.value as List)
              QuestionChoice(
                id: choice['id'] as String,
                label: choice['label'] as String,
                actionValue: choice['action_value'] as String,
              ),
          ],
      },
    );
  }

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
  final String? branchQuestionId;
  final Map<String, List<QuestionChoice>> branchChoices;

  ClarificationQuestion toEntity() {
    return ClarificationQuestion(
      id: id,
      title: title,
      options: options,
      step: step,
      totalSteps: totalSteps,
      selectedOption: selectedOption,
      selectedOptionId: selectedOptionId,
      dimension: dimension,
      choices: choices,
      branchOptions: branchOptions,
      branchTitles: branchTitles,
      branchQuestionId: branchQuestionId,
      branchChoices: branchChoices,
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
    this.priceDisplay,
    this.unitDisplay,
    this.statusDisplay,
  });

  factory RecommendedItemModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawPrice = json['price'];
    final rawName = json['item_name'] ?? json['name'] ?? json['title'];
    final rawImageUrl =
        json['image_url'] ??
        ((json['image_urls'] is List && (json['image_urls'] as List).isNotEmpty)
            ? (json['image_urls'] as List).first
            : null);
    final rawUnit = json['unit'] ?? json['price_unit'] ?? json['type'];

    return RecommendedItemModel(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId'),
      name: _stringValue(rawName, fallback: 'อุปกรณ์แนะนำ'),
      price: rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse('$rawPrice'),
      unit: _stringValue(rawUnit, fallback: 'วัน'),
      imageUrl: _stringValue(rawImageUrl),
      status: _nullableString(json['status']),
      category: _nullableString(json['category']),
      description: _nullableString(json['description']),
      priceDisplay: _nullableString(json['price_display']),
      unitDisplay: _nullableString(json['unit_display']),
      statusDisplay: _nullableString(json['status_display']),
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
  final String? priceDisplay;
  final String? unitDisplay;
  final String? statusDisplay;

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
      priceDisplay: priceDisplay,
      unitDisplay: unitDisplay,
      statusDisplay: statusDisplay,
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
