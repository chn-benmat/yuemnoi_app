import 'package:equatable/equatable.dart';

import '../../domain/entities/chat_message.dart';

class ChatbotState extends Equatable {
  const ChatbotState({
    required this.messages,
    this.isSending = false,
    this.errorMessage,
  });

  factory ChatbotState.initial() {
    return const ChatbotState(
      messages: [
        ChatMessage(
          role: ChatMessageRole.assistant,
          content:
              'สวัสดีค่ะ ฉันคือ Yuemnoi ผู้ช่วยแนะนำอุปกรณ์เช่า '
              'มีอะไรให้ช่วยวันนี้คะ',
        ),
      ],
    );
  }

  final List<ChatMessage> messages;
  final bool isSending;
  final String? errorMessage;

  ChatbotState copyWith({
    List<ChatMessage>? messages,
    bool? isSending,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatbotState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [messages, isSending, errorMessage];
}
