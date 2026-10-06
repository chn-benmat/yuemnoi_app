import 'package:equatable/equatable.dart';
import '../../domain/entities/chat_context.dart';
import '../../domain/entities/chat_turn_timing.dart';

sealed class ChatbotEvent extends Equatable {
  const ChatbotEvent();

  @override
  List<Object?> get props => [];
}

class ChatbotMessageSubmitted extends ChatbotEvent {
  const ChatbotMessageSubmitted(
    this.query, {
    this.isVisibleInChat = true,
    this.selectedOptions = const {},
    this.questionnaireAnswers = const [],
    this.questionnaireSkipped = false,
    this.activeQuestionId,
    this.timing,
  });

  final String query;
  final bool isVisibleInChat;
  final Map<String, String> selectedOptions;
  final List<QuestionnaireAnswer> questionnaireAnswers;
  final bool questionnaireSkipped;
  final String? activeQuestionId;
  final ChatTurnTiming? timing;

  @override
  List<Object?> get props => [
    query,
    isVisibleInChat,
    selectedOptions,
    questionnaireAnswers,
    questionnaireSkipped,
    activeQuestionId,
    timing,
  ];
}

class ChatbotMessageEdited extends ChatbotEvent {
  const ChatbotMessageEdited({
    required this.index,
    required this.content,
    this.timing,
  });

  final ChatTurnTiming? timing;
  final int index;
  final String content;

  @override
  List<Object?> get props => [index, content, timing];
}

class ChatbotStreamStopped extends ChatbotEvent {
  const ChatbotStreamStopped();
}

class ChatbotResponseRendered extends ChatbotEvent {
  const ChatbotResponseRendered(this.messageId);
  final String messageId;
  @override
  List<Object?> get props => [messageId];
}
