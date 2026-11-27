import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/rental_return_session.dart';
import '../../domain/repositories/rental_return_repository.dart';
import 'rental_return_state.dart';

class RentalReturnCubit extends Cubit<RentalReturnState> {
  final RentalReturnRepository _repository;
  AudioPlayer? _audioPlayer;

  RentalReturnCubit({
    required RentalReturnRepository repository,
    AudioPlayer? audioPlayer,
  }) : _repository = repository,
       _audioPlayer = audioPlayer,
       super(
         RentalReturnState(session: RentalReturnSession.createMockSession()),
       );

  /// โหลดข้อมูลการเช่า และแยกบทบาทอัตโนมัติ (ผู้เช่า vs ผู้ให้เช่า)
  Future<void> loadSession({int? rentalId, bool? isLender}) async {
    emit(state.copyWith(status: RentalReturnStatus.loading));
    try {
      final session = await _repository.getReturnSession(rentalId);

      // กำหนดบทบาทตามผู้ใช้จริง:
      final RentalUserRole resolvedRole;
      if (isLender != null) {
        resolvedRole = isLender ? RentalUserRole.lender : RentalUserRole.renter;
      } else {
        final currentUserId =
            SupabaseConfig.isConfigured && SupabaseConfig.isInitialized
            ? SupabaseConfig.client.auth.currentUser?.id
            : null;
        if (currentUserId != null &&
            currentUserId.isNotEmpty &&
            session.lenderId.isNotEmpty &&
            currentUserId == session.lenderId) {
          resolvedRole = RentalUserRole.lender;
        } else {
          resolvedRole = RentalUserRole.renter;
        }
      }

      emit(
        state.copyWith(
          status: RentalReturnStatus.loaded,
          session: session,
          activeRole: resolvedRole,
        ),
      );

      // ถ้าเหลือเวลาน้อยกว่า 1 ชั่วโมง และยังอยู่ในขั้นตอนเช่า (สำหรับฝั่งผู้เช่า) ให้เปิดการเตือน
      if (resolvedRole == RentalUserRole.renter &&
          session.isNearDeadline &&
          session.step == RentalReturnStep.inProgress) {
        triggerUrgentAlarm();
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: RentalReturnStatus.error,
          errorMessage: 'ไม่สามารถโหลดข้อมูลการคืนได้: $e',
        ),
      );
    }
  }

  /// สลับบทบาทมุมมอง (ผู้เช่า vs ผู้ให้เช่า) สำหรับทดสอบ flow สองฝั่ง
  void switchRole(RentalUserRole role) {
    emit(state.copyWith(activeRole: role));
  }

  Future<void> refreshSession() async {
    if (state.status != RentalReturnStatus.loaded || state.isSubmitting) return;
    final current = state.session;
    try {
      final session = await _repository.getReturnSession(current.rentalId);
      if (isClosed || state.isSubmitting || state.session != current) return;
      emit(state.copyWith(session: session));
    } catch (_) {
      // ลองดึงสถานะใหม่ในรอบถัดไป
    }
  }

  Future<RentalReturnPenaltyReport> savePenaltyReport({
    required bool damaged,
    required bool late,
    required String details,
  }) async {
    if (!state.isLender ||
        state.isSubmitting ||
        state.session.step == RentalReturnStep.completed) {
      throw const RentalReturnPenaltyException(
        'บันทึกรายงานสำหรับรายการนี้ไม่ได้',
      );
    }
    emit(state.copyWith(isSubmitting: true));
    try {
      final report = await _repository.savePenaltyReport(
        rentalId: state.session.rentalId,
        damaged: damaged,
        late: late,
        details: details,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            session: state.session.copyWith(penaltyReport: report),
          ),
        );
      }
      return report;
    } finally {
      if (!isClosed) emit(state.copyWith(isSubmitting: false));
    }
  }

  Future<String> getPenaltyQr() =>
      _repository.getPenaltyQr(state.session.rentalId);

  /// กระตุ้นการแจ้งเตือนฉุกเฉินกึ่งนาฬิกาปลุก (Urgent Alarm)
  Future<void> triggerUrgentAlarm() async {
    emit(state.copyWith(isAlarmActive: true));

    // เล่นเสียงเตือนภัย (message_tone.wav)
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer?.play(AssetSource('sounds/message_tone.wav'));
    } catch (e) {
      debugPrint('Audio play note: $e');
    }
  }

  Future<void> dismissAlarm() async {
    emit(state.copyWith(isAlarmActive: false));
    try {
      await _audioPlayer?.stop();
    } catch (e) {
      debugPrint('Audio stop note: $e');
    }
  }

  /// ร้านค้าตรวจรับอุปกรณ์และยืนยันว่ารายการคืนเสร็จแล้ว
  Future<void> confirmMerchantReceipt() async {
    if (state.isRenter ||
        state.isSubmitting ||
        state.session.step == RentalReturnStep.completed) {
      return;
    }
    emit(state.copyWith(isSubmitting: true));

    try {
      await _repository.confirmMerchantReceipt(
        rentalId: state.session.rentalId,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          isSubmitting: false,
          session: state.session.copyWith(
            step: RentalReturnStep.completed,
            completedAt: DateTime.now(),
          ),
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'ไม่สามารถยืนยันรับอุปกรณ์คืนได้: $e',
        ),
      );
    }
  }

  /// รีเซ็ตสำหรับทดสอบใหม่อีกรอบ
  void resetDemo() {
    _audioPlayer?.stop();
    emit(
      RentalReturnState(
        status: RentalReturnStatus.loaded,
        session: RentalReturnSession.createMockSession(),
        activeRole: state.activeRole,
      ),
    );
  }

  @override
  Future<void> close() {
    _audioPlayer?.dispose();
    return super.close();
  }
}
