import 'package:equatable/equatable.dart';

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
  });

  final String query;
  final bool isVisibleInChat;
  final Map<String, String> selectedOptions;

  @override
  List<Object?> get props => [query, isVisibleInChat, selectedOptions];
}

class ChatbotMessageEdited extends ChatbotEvent {
  const ChatbotMessageEdited({required this.index, required this.content});

  final int index;
  final String content;

  @override
  List<Object?> get props => [index, content];
}

class ChatbotStreamStopped extends ChatbotEvent {
  const ChatbotStreamStopped();
}
