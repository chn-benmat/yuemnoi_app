import 'package:equatable/equatable.dart';
import '../../domain/entities/chat_conversation.dart';

abstract class CallEvent extends Equatable {
  const CallEvent();

  @override
  List<Object?> get props => [];
}

class CallStarted extends CallEvent {
  const CallStarted({
    required this.conversation,
    this.isCaller = true,
    this.sessionId,
  });

  final ChatConversation conversation;
  final bool isCaller;
  final String? sessionId;

  @override
  List<Object?> get props => [conversation, isCaller, sessionId];
}

class CallAccepted extends CallEvent {
  const CallAccepted();
}

class CallTimerTicked extends CallEvent {
  const CallTimerTicked(this.durationSeconds);

  final int durationSeconds;

  @override
  List<Object?> get props => [durationSeconds];
}

class CallMuteToggled extends CallEvent {
  const CallMuteToggled();
}

class CallSpeakerToggled extends CallEvent {
  const CallSpeakerToggled();
}

class CallEndedEvent extends CallEvent {
  const CallEndedEvent({this.reason, this.isRejected = false});

  final String? reason;
  final bool isRejected;

  @override
  List<Object?> get props => [reason, isRejected];
}
