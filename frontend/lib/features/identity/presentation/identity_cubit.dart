import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/identity_repository.dart';

class IdentityState {
  const IdentityState({
    this.status,
    this.busy = false,
    this.error,
    this.session,
    this.captureUntil,
    this.sent = false,
  });
  final IdentityStatus? status;
  final bool busy, sent;
  final String? error, session;
  final DateTime? captureUntil;
}

class IdentityCubit extends Cubit<IdentityState> {
  IdentityCubit(this.repository) : super(const IdentityState());
  final IdentityRepository repository;
  void resetCapture() {
    if (state.busy) return;
    emit(
      IdentityState(
        status: IdentityStatus({
          ...?state.status?.data,
          'request': null,
          'profile': null,
        }),
      ),
    );
  }

  Future<void> load() async {
    if (state.busy) return;
    final previous = state;
    emit(
      IdentityState(
        status: previous.status,
        session: previous.session,
        captureUntil: previous.captureUntil,
        busy: true,
      ),
    );
    try {
      final s = await repository.status();
      final request = s.request;
      final until = DateTime.tryParse(
        request['capture_until']?.toString() ?? '',
      );
      final resume =
          request['status'] == 'capture' &&
          until != null &&
          until.isAfter(DateTime.now());
      if (!isClosed) {
        emit(
          IdentityState(
            status: s,
            session: resume ? request['id'] as String? : null,
            captureUntil: resume ? until : null,
          ),
        );
      }
    } on IdentityFailure catch (e) {
      if (!isClosed) {
        emit(
          IdentityState(
            status: previous.status,
            session: previous.session,
            captureUntil: previous.captureUntil,
            error: e.message,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          IdentityState(
            status: previous.status,
            session: previous.session,
            captureUntil: previous.captureUntil,
            error: 'โหลดสถานะไม่ได้ กรุณาลองใหม่',
          ),
        );
      }
    }
  }

  Future<void> begin(String birthDate) async {
    if (state.busy) return;
    if (!identityValidBirthDate(birthDate)) {
      emit(
        IdentityState(
          status: state.status,
          error: 'กรุณาตรวจวันเกิดให้ถูกต้อง',
        ),
      );
      return;
    }
    emit(IdentityState(status: state.status, busy: true));
    try {
      final session = await repository.begin(birthDate);
      if (!isClosed) {
        emit(
          IdentityState(
            status: IdentityStatus({
              ...?state.status?.data,
              'request': {...session, 'status': 'capture'},
            }),
            session: session['id'] as String,
            captureUntil: DateTime.parse(session['capture_until'] as String),
          ),
        );
      }
    } on IdentityFailure catch (e) {
      if (!isClosed) {
        emit(IdentityState(status: state.status, error: e.message));
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          IdentityState(
            status: state.status,
            error: 'เริ่มคำขอยืนยันตัวตนไม่ได้ กรุณาลองใหม่',
          ),
        );
      }
    }
  }

  Future<bool> submit(
    Map<String, String> fields,
    Uint8List card,
    Uint8List selfie,
  ) async {
    if (state.busy ||
        state.sent ||
        state.status?.request['status'] == 'pending') {
      return false;
    }
    final birthDate = fields['birth_date'] ?? '';
    if (!identityValidBirthDate(birthDate)) {
      emit(
        IdentityState(
          status: state.status,
          session: state.session,
          captureUntil: state.captureUntil,
          error: 'กรุณาตรวจวันเกิดให้ถูกต้อง',
        ),
      );
      return false;
    }
    var active = state;
    emit(
      IdentityState(
        status: active.status,
        session: active.session,
        captureUntil: active.captureUntil,
        busy: true,
      ),
    );
    try {
      // เริ่มคำขอหลังกรอกครบ และใช้รอบเดิมที่ยังไม่หมดอายุก่อนอัปโหลดภาพ
      if (active.session == null ||
          active.captureUntil?.isAfter(DateTime.now()) != true) {
        final session = await repository.begin(birthDate);
        if (isClosed) return false;
        active = IdentityState(
          status: IdentityStatus({
            ...?active.status?.data,
            'request': {...session, 'status': 'capture'},
          }),
          session: session['id'] as String,
          captureUntil: DateTime.parse(session['capture_until'] as String),
        );
      }
      if (active.session!.isEmpty ||
          active.captureUntil?.isAfter(DateTime.now()) != true) {
        throw const IdentityFailure('เริ่มคำขอไม่ได้ กรุณาลองส่งอีกครั้ง');
      }
      await repository.submit(active.session!, fields, card, selfie);
      if (!isClosed) {
        // backend รับหลักฐานแล้ว แสดงผลทันทีโดยไม่รอคำขอสถานะอีกเที่ยว
        emit(
          IdentityState(
            status: IdentityStatus({
              ...?active.status?.data,
              'request': {'id': active.session, 'status': 'pending'},
            }),
            sent: true,
          ),
        );
        unawaited(_refreshSubmitted(active.session!));
      }
      return true;
    } on IdentityFailure catch (e) {
      if (!isClosed) {
        emit(
          IdentityState(
            status: active.status,
            session: active.session,
            captureUntil: active.captureUntil,
            error: e.message,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          IdentityState(
            status: active.status,
            session: active.session,
            captureUntil: active.captureUntil,
            error: 'ส่งไม่สำเร็จ ข้อมูลยังอยู่ ลองส่งอีกครั้งหรือเช็กสถานะ',
          ),
        );
      }
    }
    return false;
  }

  Future<void> _refreshSubmitted(String session) async {
    bool current() =>
        !isClosed && state.sent && state.status?.request['id'] == session;
    try {
      final status = await repository.status();
      // ผลที่มาช้าต้องไม่ทับการโหลดหรือรอบยืนยันใหม่
      if (current()) emit(IdentityState(status: status, sent: true));
    } catch (_) {
      if (!current()) return;
      emit(
        IdentityState(
          status: state.status,
          sent: true,
          error: 'ส่งคำขอแล้ว แต่โหลดสถานะล่าสุดไม่ได้ กรุณาเช็กสถานะอีกครั้ง',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    repository.close();
    return super.close();
  }
}
