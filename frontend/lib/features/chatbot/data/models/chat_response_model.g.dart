// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_response_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatResponseModel _$ChatResponseModelFromJson(Map<String, dynamic> json) =>
    ChatResponseModel(
      answer: ChatResponseModel._answer(json['answer']),
      recommendedItems: ChatResponseModel._items(json['recommended_items']),
      suggestedReplies: json['suggested_replies'] == null
          ? const []
          : _strings(json['suggested_replies']),
      questions: json['questions'] == null
          ? const []
          : ChatResponseModel._questions(json['questions']),
      thought: _nullableString(json['thought']),
      searchSources: json['search_sources'] == null
          ? const []
          : ChatResponseModel._sources(json['search_sources']),
      searchQuery: _nullableString(json['search_query']),
      context: ChatContextModel.fromJson(json['context']),
      references: _readList(json, 'references') == null
          ? const []
          : ChatContextModel.references(_readList(json, 'references')),
      understanding: ChatUnderstandingModel.fromJson(
        ChatResponseModel._readUnderstanding(json, 'understanding')
            as Map<String, dynamic>,
      ),
    );

SearchSourceModel _$SearchSourceModelFromJson(Map<String, dynamic> json) =>
    SearchSourceModel(
      title: SearchSourceModel._string(json['title']),
      url: SearchSourceModel._string(json['url']),
      domain: SearchSourceModel._string(json['domain']),
      snippet: SearchSourceModel._optionalString(json['snippet']),
    );

ClarificationQuestionModel _$ClarificationQuestionModelFromJson(
  Map<String, dynamic> json,
) => ClarificationQuestionModel(
  id: ClarificationQuestionModel._string(json['id']),
  title: ClarificationQuestionModel._string(json['title']),
  options: _strings(json['options']),
  step: json['step'] == null
      ? 1
      : ClarificationQuestionModel._step(json['step']),
  totalSteps: json['total_steps'] == null
      ? 2
      : ClarificationQuestionModel._totalSteps(json['total_steps']),
  selectedOption: ClarificationQuestionModel._optionalString(
    json['selected_option'],
  ),
  selectedOptionId: json['selected_option_id'] as String?,
  dimension: json['dimension'] as String? ?? '',
  choices: _readList(json, 'choices') == null
      ? const []
      : ClarificationQuestionModel._choices(_readList(json, 'choices')),
  branchOptions: ClarificationQuestionModel._branchOptions(
    json['branch_options'],
  ),
  branchTitles: ClarificationQuestionModel._branchTitles(json['branch_titles']),
  branchQuestionId: json['branch_question_id'] as String?,
  branchChoices: _readMap(json, 'branch_choices') == null
      ? const {}
      : ClarificationQuestionModel._branchChoices(
          _readMap(json, 'branch_choices'),
        ),
);

RecommendedItemModel _$RecommendedItemModelFromJson(
  Map<String, dynamic> json,
) => RecommendedItemModel(
  id: _integer(json['id']),
  name: RecommendedItemModel._name(
    RecommendedItemModel._readName(json, 'name'),
  ),
  price: RecommendedItemModel._price(json['price']),
  unit: RecommendedItemModel._unit(
    RecommendedItemModel._readUnit(json, 'unit'),
  ),
  imageUrl: RecommendedItemModel._image(
    RecommendedItemModel._readImageUrl(json, 'image_url'),
  ),
  status: RecommendedItemModel._nullableString(json['status']),
  category: RecommendedItemModel._nullableString(json['category']),
  description: RecommendedItemModel._nullableString(json['description']),
  priceDisplay: RecommendedItemModel._nullableString(json['price_display']),
  unitDisplay: RecommendedItemModel._nullableString(json['unit_display']),
  statusDisplay: RecommendedItemModel._nullableString(json['status_display']),
);
