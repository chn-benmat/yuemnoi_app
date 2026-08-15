import 'package:equatable/equatable.dart';
import '../../domain/entities/chat_conversation.dart';

enum CallStatus { initial, dialing, ringing, connected, ended }

class CallState extends Equatable {
  const CallState({
    this.status = CallStatus.initial,
    this.conversation,
    this.sessionId,
    this.isCaller = true,
    this.durationSeconds = 0,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.endReason,
    this.errorMessage,
  });

  final CallStatus status;
  final ChatConversation? conversation;
  final String? sessionId;
  final bool isCaller;
  final int durationSeconds;
  final bool isMuted;
  final bool isSpeakerOn;
  final String? endReason;
  final String? errorMessage;

  String get formattedDuration {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get statusLabel {
    switch (status) {
      case CallStatus.initial:
      case CallStatus.dialing:
        return 'กำลังโทรออก...';
      case CallStatus.ringing:
        return isCaller ? 'กำลังเรียกสาย...' : 'สายเรียกเข้า...';
      case CallStatus.connected:
        return formattedDuration;
      case CallStatus.ended:
        return endReason ?? 'สิ้นสุดการโทร';
    }
  }

  CallState copyWith({
    CallStatus? status,
    ChatConversation? conversation,
    String? sessionId,
    bool? isCaller,
    int? durationSeconds,
    bool? isMuted,
    bool? isSpeakerOn,
    String? endReason,
    String? errorMessage,
  }) {
    return CallState(
      status: status ?? this.status,
      conversation: conversation ?? this.conversation,
      sessionId: sessionId ?? this.sessionId,
      isCaller: isCaller ?? this.isCaller,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      endReason: endReason ?? this.endReason,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        conversation,
        sessionId,
        isCaller,
        durationSeconds,
        isMuted,
        isSpeakerOn,
        endReason,
        errorMessage,
      ];
}
