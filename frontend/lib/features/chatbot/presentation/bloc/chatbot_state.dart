import 'package:equatable/equatable.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chatbot_failure.dart';

class ChatbotState extends Equatable {
  const ChatbotState({
    required this.messages,
    this.isSending = false,
    this.errorMessage,
    this.currentStatusMessage,
    this.requestStartTime,
    this.failure,
  });

  static const defaultInitialSuggestions = [
    'ช่วยหากล้องสำหรับถ่ายงานให้หน่อย',
    'ช่วยหาอุปกรณ์ไปแคมป์ปิ้งให้หน่อย',
    'ช่วยหาคอมพิวเตอร์ทำโปรเจกต์ให้หน่อย',
  ];

  factory ChatbotState.initial() {
    return const ChatbotState(messages: []);
  }

  final List<ChatMessage> messages;
  final bool isSending;
  final String? errorMessage;
  final String? currentStatusMessage;
  final DateTime? requestStartTime;
  final ChatbotFailure? failure;

  ChatbotState copyWith({
    List<ChatMessage>? messages,
    bool? isSending,
    String? errorMessage,
    bool clearError = false,
    String? currentStatusMessage,
    bool clearStatus = false,
    DateTime? requestStartTime,
    bool clearStartTime = false,
    ChatbotFailure? failure,
    bool clearFailure = false,
  }) {
    return ChatbotState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      currentStatusMessage: clearStatus
          ? null
          : currentStatusMessage ?? this.currentStatusMessage,
      requestStartTime: clearStartTime
          ? null
          : requestStartTime ?? this.requestStartTime,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [
    messages,
    isSending,
    errorMessage,
    currentStatusMessage,
    requestStartTime,
    failure,
  ];
}
