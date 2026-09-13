import 'package:equatable/equatable.dart';

import '../../domain/entities/chat_message.dart';

class ChatbotState extends Equatable {
  const ChatbotState({
    required this.messages,
    this.isSending = false,
    this.errorMessage,
    this.currentStatusMessage,
    this.requestStartTime,
  });

  static const defaultInitialSuggestions = [
    'แนะนำอุปกรณ์เช่าหน่อย',
    'วิธีการเช่าอุปกรณ์',
    'วิธีปล่อยเช่าอุปกรณ์',
  ];

  factory ChatbotState.initial() {
    return const ChatbotState(
      messages: [],
    );
  }

  final List<ChatMessage> messages;
  final bool isSending;
  final String? errorMessage;
  final String? currentStatusMessage;
  final DateTime? requestStartTime;

  ChatbotState copyWith({
    List<ChatMessage>? messages,
    bool? isSending,
    String? errorMessage,
    bool clearError = false,
    String? currentStatusMessage,
    bool clearStatus = false,
    DateTime? requestStartTime,
    bool clearStartTime = false,
  }) {
    return ChatbotState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      currentStatusMessage:
          clearStatus ? null : currentStatusMessage ?? this.currentStatusMessage,
      requestStartTime:
          clearStartTime ? null : requestStartTime ?? this.requestStartTime,
    );
  }

  @override
  List<Object?> get props => [
    messages,
    isSending,
    errorMessage,
    currentStatusMessage,
    requestStartTime,
  ];
}
