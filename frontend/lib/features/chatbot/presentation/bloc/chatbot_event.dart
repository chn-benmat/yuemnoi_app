import 'package:equatable/equatable.dart';

sealed class ChatbotEvent extends Equatable {
  const ChatbotEvent();

  @override
  List<Object?> get props => [];
}

class ChatbotMessageSubmitted extends ChatbotEvent {
  const ChatbotMessageSubmitted(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

class ChatbotMessageEdited extends ChatbotEvent {
  const ChatbotMessageEdited({required this.index, required this.content});

  final int index;
  final String content;

  @override
  List<Object?> get props => [index, content];
}

class ChatbotFeedbackSubmitted extends ChatbotEvent {
  const ChatbotFeedbackSubmitted({
    required this.messageIndex,
    required this.isLiked,
    this.reasonCategory,
    this.feedbackComment,
  });

  final int messageIndex;
  final bool isLiked;
  final String? reasonCategory;
  final String? feedbackComment;

  @override
  List<Object?> get props => [
    messageIndex,
    isLiked,
    reasonCategory,
    feedbackComment,
  ];
}
