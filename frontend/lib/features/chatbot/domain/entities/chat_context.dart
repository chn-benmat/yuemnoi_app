import 'package:equatable/equatable.dart';
import 'chat_message.dart';

class ConversationFact extends Equatable {
  const ConversationFact({
    required this.dimension,
    required this.value,
    required this.sourceMessageIds,
  });
  final String dimension;
  final String value;
  final List<String> sourceMessageIds;
  @override
  List<Object?> get props => [dimension, value, sourceMessageIds];
}

class ChatSessionContext extends Equatable {
  const ChatSessionContext({
    required this.sessionId,
    required this.userGoal,
    this.budgetMax,
    this.budgetUnit,
    this.intendedUse,
    this.categories = const [],
    this.targetItems = const [],
    this.knownFacts = const [],
    this.userConstraints = const [],
    this.excludedItems = const [],
    this.referencedItemIds = const [],
    this.clarificationDeclined = false,
    this.questions = const [],
  });
  final String sessionId;
  final String userGoal;
  final double? budgetMax;
  final String? budgetUnit;
  final String? intendedUse;
  final List<String> categories;
  final List<String> targetItems;
  final List<ConversationFact> knownFacts;
  final List<ConversationFact> userConstraints;
  final List<String> excludedItems;
  final List<String> referencedItemIds;
  final bool clarificationDeclined;
  final List<ClarificationQuestion> questions;
  @override
  List<Object?> get props => [
    sessionId,
    userGoal,
    budgetMax,
    budgetUnit,
    intendedUse,
    categories,
    targetItems,
    knownFacts,
    userConstraints,
    excludedItems,
    referencedItemIds,
    clarificationDeclined,
    questions,
  ];
}

class QuestionnaireAnswer extends Equatable {
  const QuestionnaireAnswer({
    required this.questionId,
    this.optionId,
    this.text,
  }) : assert((optionId == null) != (text == null));
  final String questionId;
  final String? optionId;
  final String? text;
  @override
  List<Object?> get props => [questionId, optionId, text];
}

class QuestionChoice extends Equatable {
  const QuestionChoice({
    required this.id,
    required this.label,
    required this.actionValue,
  });
  final String id;
  final String label;
  final String actionValue;
  @override
  List<Object?> get props => [id, label, actionValue];
}

class EvidenceReference extends Equatable {
  const EvidenceReference({
    required this.id,
    required this.kind,
    required this.title,
    required this.reference,
    this.reviewedAt,
    this.contentSha256,
  });
  final String id;
  final String kind;
  final String title;
  final String reference;
  final String? reviewedAt;
  final String? contentSha256;
  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    reference,
    reviewedAt,
    contentSha256,
  ];
}
