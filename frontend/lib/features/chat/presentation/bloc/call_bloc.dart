import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../data/datasources/call_remote_data_source.dart';
import '../../data/services/call_audio_service.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import 'call_event.dart';
import 'call_state.dart';

class CallBloc extends Bloc<CallEvent, CallState> {
  CallBloc({
    SendChatMessageUseCase? sendMessage,
    CallRemoteDataSource? callRemoteDataSource,
    CallAudioService? audioService,
  })  : _sendMessage = sendMessage,
        _callRemoteDataSource = callRemoteDataSource,
        _audioService = audioService,
        super(const CallState()) {
    on<CallStarted>(_onCallStarted);
    on<CallAccepted>(_onCallAccepted);
    on<CallTimerTicked>(_onCallTimerTicked);
    on<CallMuteToggled>(_onCallMuteToggled);
    on<CallSpeakerToggled>(_onCallSpeakerToggled);
    on<CallEndedEvent>(_onCallEnded);
  }

  final SendChatMessageUseCase? _sendMessage;
  final CallRemoteDataSource? _callRemoteDataSource;
  final CallAudioService? _audioService;

  Timer? _callTimer;
  Timer? _connectTimer;
  StreamSubscription<String>? _statusSubscription;
  int _seconds = 0;
  DateTime? _callStartedAt;

  Future<void> _onCallStarted(
    CallStarted event,
    Emitter<CallState> emit,
  ) async {
    _seconds = 0;
    _callStartedAt = DateTime.now();
    _callTimer?.cancel();
    _connectTimer?.cancel();
    await _statusSubscription?.cancel();

    String? sessionId = event.sessionId;

    // ถ้าเป็นผู้โทรออก ให้สร้าง session ใน Supabase และเล่นเสียงรอสาย
    if (event.isCaller) {
      _audioService?.playDialTone();
      if (_callRemoteDataSource != null) {
        sessionId = await _callRemoteDataSource.createCallSession(
          conversationId: event.conversation.id,
          receiverId: event.conversation.otherUserId,
        );
      }
    }

    emit(state.copyWith(
      status: CallStatus.ringing,
      conversation: event.conversation,
      isCaller: event.isCaller,
      sessionId: sessionId,
      durationSeconds: 0,
      isMuted: false,
      isSpeakerOn: false,
    ));

    // ฟังสถานะ Realtime จาก Supabase
    if (sessionId != null && sessionId.isNotEmpty && _callRemoteDataSource != null) {
      _statusSubscription = _callRemoteDataSource
          .streamCallStatus(sessionId)
          .listen((status) {
        if (status == 'accepted') {
          add(const CallAccepted());
        } else if (status == 'rejected' || status == 'ended') {
          add(CallEndedEvent(isRejected: status == 'rejected'));
        }
      });
    } else if (event.isCaller) {
      // Fallback timer simulation สำหรับ Widget Testing
      _connectTimer = Timer(const Duration(seconds: 2), () {
        if (!isClosed && state.status == CallStatus.ringing) {
          add(const CallAccepted());
        }
      });
    }
  }

  void _onCallAccepted(
    CallAccepted event,
    Emitter<CallState> emit,
  ) {
    // หยุดเสียงรอสายเมื่อสายถูกรับ
    _audioService?.stopAll();
    _connectTimer?.cancel();

    emit(state.copyWith(status: CallStatus.connected));

    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      if (!isClosed) {
        add(CallTimerTicked(_seconds));
      }
    });
  }

  void _onCallTimerTicked(
    CallTimerTicked event,
    Emitter<CallState> emit,
  ) {
    if (state.status == CallStatus.connected) {
      emit(state.copyWith(durationSeconds: event.durationSeconds));
    }
  }

  void _onCallMuteToggled(
    CallMuteToggled event,
    Emitter<CallState> emit,
  ) {
    emit(state.copyWith(isMuted: !state.isMuted));
  }

  void _onCallSpeakerToggled(
    CallSpeakerToggled event,
    Emitter<CallState> emit,
  ) {
    emit(state.copyWith(isSpeakerOn: !state.isSpeakerOn));
  }

  Future<void> _onCallEnded(
    CallEndedEvent event,
    Emitter<CallState> emit,
  ) async {
    _audioService?.stopAll();
    _callTimer?.cancel();
    _connectTimer?.cancel();
    await _statusSubscription?.cancel();

    final finalDuration = state.durationSeconds;
    final conv = state.conversation;
    final formatted = state.formattedDuration;
    final sessionId = state.sessionId;

    emit(state.copyWith(
      status: CallStatus.ended,
      endReason: event.reason ?? 'สิ้นสุดการโทร',
    ));

    // อัปเดตสถานะใน Supabase
    if (sessionId != null && sessionId.isNotEmpty && _callRemoteDataSource != null) {
      await _callRemoteDataSource.updateCallStatus(
        sessionId: sessionId,
        status: event.isRejected ? 'rejected' : 'ended',
      );
    }

    // บันทึกประวัติการโทรเข้าห้องแชทอัตโนมัติ พร้อมเวลาเริ่มโทรและวางสาย
    if (conv != null && _sendMessage != null && state.isCaller) {
      final now = DateTime.now();
      final startTime = _callStartedAt ?? now.subtract(Duration(seconds: finalDuration));
      final startTimeStr = DateFormat('HH:mm').format(startTime);
      final endTimeStr = DateFormat('HH:mm').format(now);

      final String logMessage;
      if (event.isRejected) {
        logMessage = '📞 สายถูกปฏิเสธ';
      } else if (finalDuration > 0) {
        final hours = finalDuration ~/ 3600;
        final minutes = (finalDuration % 3600) ~/ 60;
        final seconds = finalDuration % 60;

        final String durationText;
        if (hours > 0) {
          if (minutes > 0 && seconds > 0) {
            durationText = '$hours ชั่วโมง $minutes นาที $seconds วิ';
          } else if (minutes > 0) {
            durationText = '$hours ชั่วโมง $minutes นาที';
          } else if (seconds > 0) {
            durationText = '$hours ชั่วโมง $seconds วิ';
          } else {
            durationText = '$hours ชั่วโมง';
          }
        } else if (minutes > 0) {
          durationText =
              seconds > 0 ? '$minutes นาที $seconds วิ' : '$minutes นาที';
        } else {
          durationText = '$seconds วิ';
        }
        logMessage = '📞 โทรด้วยเสียง • $durationText';
      } else {
        logMessage =
            (event.reason == 'ยกเลิกการโทร' || event.reason == 'วางสายแล้ว')
                ? '📞 วางสายแล้ว'
                : '📞 ไม่ได้รับสาย';
      }

      try {
        await _sendMessage(
          conversationId: conv.id,
          message: logMessage,
        );
      } catch (_) {}
    }
  }

  @override
  Future<void> close() {
    _audioService?.stopAll();
    _callTimer?.cancel();
    _connectTimer?.cancel();
    _statusSubscription?.cancel();
    return super.close();
  }
}
