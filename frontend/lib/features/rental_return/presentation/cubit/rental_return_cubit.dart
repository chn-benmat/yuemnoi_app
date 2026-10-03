import 'dart:math';

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
  })  : _repository = repository,
        _audioPlayer = audioPlayer,
        super(
          RentalReturnState(
            session: RentalReturnSession.createMockSession(),
          ),
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
        final currentUserId = SupabaseConfig.isConfigured && SupabaseConfig.isInitialized
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

  /// กระตุ้นการแจ้งเตือนฉุกเฉินกึ่งนาฬิกาปลุก (Urgent Alarm)
  Future<void> triggerUrgentAlarm() async {
    emit(
      state.copyWith(
        isAlarmActive: true,
        session: state.session.copyWith(step: RentalReturnStep.nearReturnAlert),
      ),
    );

    // เล่นเสียงเตือนภัย (message_tone.wav)
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer?.play(AssetSource('sounds/message_tone.wav'));
    } catch (e) {
      debugPrint('Audio play note: $e');
    }
  }

  /// ผู้เช่ากดปุ่มใน Alarm เพื่อปิดเสียงและเข้าสู่ขั้นตอนถ่ายภาพสดทันที
  void dismissAlarmAndStartVerification() {
    try {
      _audioPlayer?.stop();
    } catch (_) {}

    emit(
      state.copyWith(
        isAlarmActive: false,
        session: state.session.copyWith(step: RentalReturnStep.liveVerification),
      ),
    );
  }

  /// อัปเดตรูปถ่ายของมุมที่ระบุ (Camera Only)
  void updatePhoto({
    required String angleKey,
    required String photoPath,
  }) {
    final updatedPhotos = state.session.photos.map((p) {
      if (p.angleKey == angleKey) {
        return p.copyWith(
          localPath: photoPath,
          timestamp: DateTime.now(),
          challengeCode: state.session.dynamicChallengeCode,
        );
      }
      return p;
    }).toList();

    emit(
      state.copyWith(
        session: state.session.copyWith(photos: updatedPhotos),
      ),
    );
  }

  /// ติ๊กถูกในรายการตรวจสอบสภาพ (Checklist)
  void toggleChecklist(String key, bool value) {
    final newChecklist = Map<String, bool>.from(state.session.checklist);
    newChecklist[key] = value;

    emit(
      state.copyWith(
        session: state.session.copyWith(checklist: newChecklist),
      ),
    );
  }

  /// กดส่งผลตรวจสภาพสดไปยังร้านค้า
  Future<void> submitLiveConditionVerification() async {
    if (!state.session.hasAllMandatoryPhotos) {
      emit(state.copyWith(errorMessage: 'กรุณาถ่ายภาพให้ครบทั้ง 3 มุม'));
      return;
    }

    if (!state.session.isChecklistComplete) {
      emit(state.copyWith(errorMessage: 'กรุณายืนยันรายการตรวจสอบสภาพเครื่องให้ครบทุกข้อ'));
      return;
    }

    emit(state.copyWith(isSubmitting: true));

    try {
      await _repository.submitConditionVerification(
        rentalId: state.session.rentalId,
        photos: state.session.photos,
        checklist: state.session.checklist,
      );

      emit(
        state.copyWith(
          isSubmitting: false,
          session: state.session.copyWith(step: RentalReturnStep.awaitingHandover),
          successMessage: 'ส่งภาพถ่ายสภาพเครื่องเรียบร้อย! โปรดนำเครื่องไปส่งคืนที่จุดนัดพบ',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'ส่งข้อมูลไม่สำเร็จ: $e',
        ),
      );
    }
  }

  /// ฝ่ายร้านค้าตรวจสอบเครื่องแล้ว & กดยืนยัน -> สร้าง Dynamic QR Code
  Future<void> confirmLenderInspection() async {
    emit(state.copyWith(isSubmitting: true));

    try {
      final now = DateTime.now();
      final otp = (100000 + Random().nextInt(900000)).toString();
      final token = 'YUEMNOI_RETURN_${state.session.rentalId}_${otp}_${now.millisecondsSinceEpoch}';
      final expiry = now.add(const Duration(minutes: 5));

      emit(
        state.copyWith(
          isSubmitting: false,
          merchantQrExpiry: expiry,
          session: state.session.copyWith(
            step: RentalReturnStep.merchantQrReady,
            isLenderConfirmed: true,
            merchantQrToken: token,
            merchantOtp: otp,
          ),
          successMessage: 'สร้าง QR Code สำหรับคืนอุปกรณ์สำเร็จ รอลูกค้าสแกน',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'ไม่สามารถสร้าง QR Code ได้: $e',
        ),
      );
    }
  }

  /// สแกน QR Code หรือกรอก OTP เพื่อจบกระบวนการคืน
  Future<bool> completeReturnWithQr(String tokenOrOtp) async {
    emit(state.copyWith(isSubmitting: true));

    try {
      final success = await _repository.completeReturnWithToken(
        rentalId: state.session.rentalId,
        tokenOrOtp: tokenOrOtp.trim(),
      );

      if (success) {
        emit(
          state.copyWith(
            isSubmitting: false,
            session: state.session.copyWith(
              step: RentalReturnStep.completed,
              completedAt: DateTime.now(),
            ),
            successMessage: 'คืนอุปกรณ์สำเร็จเรียบร้อย! คืนเงินมัดจำเข้าบัญชีของคุณแล้ว',
          ),
        );
        return true;
      } else {
        emit(
          state.copyWith(
            isSubmitting: false,
            errorMessage: 'รหัส QR หรือรหัส OTP ไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง',
          ),
        );
        return false;
      }
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'เกิดข้อผิดพลาดในการจบขั้นตอน: $e',
        ),
      );
      return false;
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
