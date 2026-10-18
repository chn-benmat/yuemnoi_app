import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/chat_message.dart';
import 'chat_context_model.dart';
import 'chat_understanding_model.dart';

part 'chat_response_model.g.dart';

@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
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

  factory ChatResponseModel.fromJson(Map<String, dynamic> json) =>
      _$ChatResponseModelFromJson(json);

  @JsonKey(fromJson: _answer)
  final String answer;
  @JsonKey(fromJson: _items)
  final List<RecommendedItemModel> recommendedItems;
  @JsonKey(fromJson: _strings)
  final List<String> suggestedReplies;
  @JsonKey(fromJson: _questions)
  final List<ClarificationQuestionModel> questions;
  @JsonKey(fromJson: _nullableString)
  final String? thought;
  @JsonKey(fromJson: _sources)
  final List<SearchSourceModel> searchSources;
  @JsonKey(fromJson: _nullableString)
  final String? searchQuery;
  @JsonKey(fromJson: ChatContextModel.fromJson)
  final ChatSessionContext? context;
  @JsonKey(readValue: _readList, fromJson: ChatContextModel.references)
  final List<EvidenceReference> references;
  @JsonKey(
    readValue: _readUnderstanding,
    fromJson: ChatUnderstandingModel.fromJson,
  )
  final ChatUnderstanding? understanding;

  static String _answer(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Chat response must contain an answer');
    }
    return value.trim();
  }

  static Object? _readUnderstanding(Map json, String key) => json;
  static List<RecommendedItemModel> _items(Object? value) =>
      _models(value, RecommendedItemModel.fromJson);
  static List<ClarificationQuestionModel> _questions(Object? value) =>
      _models(value, ClarificationQuestionModel.fromJson);
  static List<SearchSourceModel> _sources(Object? value) =>
      _models(value, SearchSourceModel.fromJson);

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

@JsonSerializable(createToJson: false)
class SearchSourceModel {
  const SearchSourceModel({
    required this.title,
    required this.url,
    required this.domain,
    this.snippet,
  });

  factory SearchSourceModel.fromJson(Map<String, dynamic> json) =>
      _$SearchSourceModelFromJson(json);

  @JsonKey(fromJson: _string)
  final String title;
  @JsonKey(fromJson: _string)
  final String url;
  @JsonKey(fromJson: _string)
  final String domain;
  @JsonKey(fromJson: _optionalString)
  final String? snippet;

  static String _string(Object? value) => value?.toString() ?? '';
  static String? _optionalString(Object? value) => value?.toString();

  SearchSource toEntity() {
    return SearchSource(
      title: title,
      url: url,
      domain: domain,
      snippet: snippet,
    );
  }
}

@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
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

  factory ClarificationQuestionModel.fromJson(Map<String, dynamic> json) =>
      _$ClarificationQuestionModelFromJson(json);

  @JsonKey(fromJson: _string)
  final String id;
  @JsonKey(fromJson: _string)
  final String title;
  @JsonKey(fromJson: _strings)
  final List<String> options;
  @JsonKey(fromJson: _step)
  final int step;
  @JsonKey(fromJson: _totalSteps)
  final int totalSteps;
  @JsonKey(fromJson: _optionalString)
  final String? selectedOption;
  final String? selectedOptionId;
  final String dimension;
  @JsonKey(readValue: _readList, fromJson: _choices)
  final List<QuestionChoice> choices;
  @JsonKey(fromJson: _branchOptions)
  final Map<String, List<String>>? branchOptions;
  @JsonKey(fromJson: _branchTitles)
  final Map<String, String>? branchTitles;
  final String? branchQuestionId;
  @JsonKey(readValue: _readMap, fromJson: _branchChoices)
  final Map<String, List<QuestionChoice>> branchChoices;

  static String _string(Object? value) => value?.toString() ?? '';
  static String? _optionalString(Object? value) => value?.toString();
  static int _step(Object? value) => _integer(value) ?? 1;
  static int _totalSteps(Object? value) => _integer(value) ?? 2;

  static List<QuestionChoice> _choices(Object? value) =>
      (value as List? ?? []).map((choice) => _choice(choice as Map)).toList();

  static QuestionChoice _choice(Map value) => QuestionChoice(
    id: value['id'] as String,
    label: value['label'] as String,
    actionValue: value['action_value'] as String,
  );

  static Map<String, List<QuestionChoice>> _branchChoices(Object? value) => {
    for (final entry in (value as Map? ?? {}).entries)
      entry.key as String: [
        for (final choice in entry.value as List) _choice(choice as Map),
      ],
  };

  static Map<String, List<String>>? _branchOptions(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.value is List)
          entry.key.toString(): [
            for (final option in entry.value as List) option.toString(),
          ],
    };
  }

  static Map<String, String>? _branchTitles(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

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

@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
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

  factory RecommendedItemModel.fromJson(Map<String, dynamic> json) =>
      _$RecommendedItemModelFromJson(json);

  @JsonKey(fromJson: _integer)
  final int? id;
  @JsonKey(readValue: _readName, fromJson: _name)
  final String name;
  @JsonKey(fromJson: _price)
  final double? price;
  @JsonKey(readValue: _readUnit, fromJson: _unit)
  final String unit;
  @JsonKey(readValue: _readImageUrl, fromJson: _image)
  final String imageUrl;
  @JsonKey(fromJson: _nullableString)
  final String? status;
  @JsonKey(fromJson: _nullableString)
  final String? category;
  @JsonKey(fromJson: _nullableString)
  final String? description;
  @JsonKey(fromJson: _nullableString)
  final String? priceDisplay;
  @JsonKey(fromJson: _nullableString)
  final String? unitDisplay;
  @JsonKey(fromJson: _nullableString)
  final String? statusDisplay;

  static Object? _readName(Map json, String key) =>
      json['item_name'] ?? json[key] ?? json['title'];
  static Object? _readUnit(Map json, String key) =>
      json[key] ?? json['price_unit'] ?? json['type'];
  static Object? _readImageUrl(Map json, String key) =>
      json[key] ??
      ((json['image_urls'] is List && (json['image_urls'] as List).isNotEmpty)
          ? (json['image_urls'] as List).first
          : null);
  static double? _price(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');
  static String _name(Object? value) =>
      _stringValue(value, fallback: 'อุปกรณ์แนะนำ');
  static String _unit(Object? value) => _stringValue(value, fallback: 'วัน');
  static String _image(Object? value) => _stringValue(value);

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

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

Object? _readList(Map json, String key) => json[key] ?? [];
Object? _readMap(Map json, String key) => json[key] ?? {};

List<T> _models<T>(Object? value, T Function(Map<String, dynamic>) fromJson) =>
    value is List
    ? value
          .whereType<Map>()
          .map(
            (map) => fromJson(
              map.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false)
    : List<T>.empty(growable: false);

List<String> _strings(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false)
    : const <String>[];

String? _nullableString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
