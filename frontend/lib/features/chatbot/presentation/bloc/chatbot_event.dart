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
