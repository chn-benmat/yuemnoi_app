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

  Future<void> begin(bool minor) async {
    if (state.busy) return;
    emit(IdentityState(status: state.status, busy: true));
    try {
      final session = await repository.begin(minor);
      if (!isClosed) {
        emit(
          IdentityState(
            status: state.status,
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
            error: 'เริ่มถ่ายภาพไม่ได้ กรุณาลองใหม่',
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
    if (state.busy || state.session == null) return false;
    if (state.captureUntil == null ||
        !state.captureUntil!.isAfter(DateTime.now())) {
      emit(
        IdentityState(
          status: state.status,
          error: 'รอบถ่ายภาพหมดอายุ กรุณาโหลดสถานะและเริ่มใหม่',
        ),
      );
      return false;
    }
    final previous = state;
    emit(
      IdentityState(
        status: previous.status,
        session: previous.session,
        captureUntil: previous.captureUntil,
        busy: true,
      ),
    );
    var accepted = false;
    try {
      await repository.submit(previous.session!, fields, card, selfie);
      accepted = true;
      final status = await repository.status();
      if (!isClosed) emit(IdentityState(status: status, sent: true));
      return true;
    } on IdentityFailure catch (e) {
      if (accepted) return _submittedWithoutRefresh(previous);
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
      if (accepted) return _submittedWithoutRefresh(previous);
      if (!isClosed) {
        emit(
          IdentityState(
            status: previous.status,
            session: previous.session,
            captureUntil: previous.captureUntil,
            error: 'ส่งไม่สำเร็จ ข้อมูลยังอยู่ ลองส่งอีกครั้งหรือเช็กสถานะ',
          ),
        );
      }
    }
    return false;
  }

  bool _submittedWithoutRefresh(IdentityState previous) {
    if (!isClosed) {
      emit(
        IdentityState(
          status: IdentityStatus({
            ...?previous.status?.data,
            'request': {'id': previous.session, 'status': 'pending'},
          }),
          sent: true,
          error: 'ส่งคำขอแล้ว แต่โหลดสถานะล่าสุดไม่ได้ กรุณาเช็กสถานะอีกครั้ง',
        ),
      );
    }
    return true;
  }

  Future<Map<String, String>?> readCard(Uint8List card) async {
    if (state.busy || state.session == null) return null;
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
      final fields = await repository.readCard(previous.session!, card);
      if (!isClosed) {
        emit(
          IdentityState(
            status: previous.status,
            session: previous.session,
            captureUntil: previous.captureUntil,
          ),
        );
      }
      return fields;
    } catch (_) {
      if (!isClosed) {
        emit(
          IdentityState(
            status: previous.status,
            session: previous.session,
            captureUntil: previous.captureUntil,
            error: 'อ่านบัตรไม่สำเร็จ คุณกรอกข้อมูลเองได้ หรือลองอ่านอีกครั้ง',
          ),
        );
      }
      return null;
    }
  }

  Future<bool> guardian(
    String child,
    String relationship,
    Uint8List image,
  ) async {
    if (state.busy) return false;
    emit(IdentityState(status: state.status, busy: true));
    try {
      await repository.guardian(child, relationship, image);
      if (!isClosed) emit(IdentityState(status: state.status, sent: true));
      return true;
    } on IdentityFailure catch (e) {
      if (!isClosed) {
        emit(IdentityState(status: state.status, error: e.message));
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          IdentityState(
            status: state.status,
            error: 'ส่งคำขอไม่สำเร็จ กรุณาลองใหม่',
          ),
        );
      }
    }
    return false;
  }

  @override
  Future<void> close() {
    repository.close();
    return super.close();
  }
}
