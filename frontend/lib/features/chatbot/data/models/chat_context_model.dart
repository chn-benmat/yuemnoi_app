import '../../domain/entities/chat_message.dart';
import 'chat_response_model.dart';

class ChatContextModel {
  static ChatSessionContext? fromJson(Object? value) {
    if (value == null) return null;
    if (value is! Map ||
        value['session_id'] is! String ||
        (value['session_id'] as String).isEmpty ||
        value['user_goal'] is! String) {
      throw const FormatException('Invalid chat context');
    }
    return ChatSessionContext(
      sessionId: value['session_id'] as String,
      userGoal: value['user_goal'] as String,
      budgetMax: (value['budget_max'] as num?)?.toDouble(),
      budgetUnit: value['budget_unit'] as String?,
      intendedUse: value['intended_use'] as String?,
      categories: _strings(value['categories']),
      targetItems: _strings(value['target_items']),
      knownFacts: _facts(value['known_facts']),
      userConstraints: _facts(value['user_constraints']),
      excludedItems: _strings(value['excluded_items']),
      referencedItemIds: _strings(value['referenced_item_ids']),
      clarificationDeclined: value['clarification_declined'] == true,
      questions: (value['questions'] as List? ?? [])
          .map(
            (q) => ClarificationQuestionModel.fromJson(
              Map<String, dynamic>.from(q as Map),
            ).toEntity(),
          )
          .toList(),
    );
  }

  static List<String> _strings(Object? value) =>
      (value as List? ?? []).cast<String>();
  static List<ConversationFact> _facts(Object? value) =>
      (value as List? ?? []).map((f) {
        final fact = f as Map;
        return ConversationFact(
          dimension: fact['dimension'] as String,
          value: fact['value'] as String,
          sourceMessageIds: _strings(fact['source_message_ids']),
        );
      }).toList();

  static Map<String, Object?> toJson(ChatSessionContext context) => {
    'session_id': context.sessionId,
    'user_goal': context.userGoal,
    'budget_max': context.budgetMax,
    'budget_unit': context.budgetUnit,
    'intended_use': context.intendedUse,
    'categories': context.categories,
    'target_items': context.targetItems,
    'known_facts': context.knownFacts.map(_fact).toList(),
    'user_constraints': context.userConstraints.map(_fact).toList(),
    'excluded_items': context.excludedItems,
    'referenced_item_ids': context.referencedItemIds,
    'clarification_declined': context.clarificationDeclined,
    'questions': context.questions.map(questionJson).toList(),
  };
  static Map<String, Object?> _fact(ConversationFact f) => {
    'dimension': f.dimension,
    'value': f.value,
    'source_message_ids': f.sourceMessageIds,
  };
  static Map<String, Object?> answerJson(QuestionnaireAnswer a) => {
    'question_id': a.questionId,
    if (a.optionId != null) 'option_id': a.optionId,
    if (a.text != null) 'text': a.text,
  };
  static Map<String, Object?> questionJson(ClarificationQuestion q) => {
    'id': q.id,
    'dimension': q.dimension,
    'title': q.title,
    'options': q.options,
    'step': q.step,
    'total_steps': q.totalSteps,
    if (q.branchQuestionId != null) 'branch_question_id': q.branchQuestionId,
    if (q.branchTitles?.isNotEmpty == true) 'branch_titles': q.branchTitles,
    if (q.branchOptions?.isNotEmpty == true) 'branch_options': q.branchOptions,
    if (q.branchChoices.isNotEmpty)
      'branch_choices': {
        for (final entry in q.branchChoices.entries)
          entry.key: [
            for (final c in entry.value)
              {'id': c.id, 'label': c.label, 'action_value': c.actionValue},
          ],
      },
    'choices': q.choices
        .map(
          (c) => {'id': c.id, 'label': c.label, 'action_value': c.actionValue},
        )
        .toList(),
  };
  static List<EvidenceReference> references(Object? value) =>
      (value as List? ?? []).map((r) {
        final ref = r as Map;
        return EvidenceReference(
          id: ref['id'] as String,
          kind: ref['kind'] as String,
          title: ref['title'] as String,
          reference: ref['reference'] as String,
          reviewedAt: ref['reviewed_at'] as String?,
          contentSha256: ref['content_sha256'] as String?,
        );
      }).toList();
}
