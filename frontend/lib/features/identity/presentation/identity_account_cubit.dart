import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/identity_account_repository.dart';
import '../domain/identity_repository.dart';

class IdentityAccountState {
  const IdentityAccountState({
    this.details,
    this.photos = const {},
    this.busy = false,
    this.loading = false,
    this.error,
    this.sent = false,
  });
  final IdentityAccountDetails? details;
  final Map<String, Uint8List> photos;
  final bool busy, loading, sent;
  final String? error;
}

class IdentityAccountCubit extends Cubit<IdentityAccountState> {
  IdentityAccountCubit(
    this.repository, {
    required IdentityConsentStore consentStore,
  }) : _consentStore = consentStore,
       super(const IdentityAccountState());
  final IdentityAccountRepository repository;
  final IdentityConsentStore _consentStore;

  Future<void> load({
    Future<void> Function(bool hasConsent)? onDetailsLoaded,
  }) async {
    if (state.busy) return;
    emit(
      IdentityAccountState(
        details: state.details,
        photos: state.photos,
        busy: true,
        loading: true,
        sent: state.sent,
      ),
    );
    try {
      final details = await repository.accountDetails();
      final hasConsent =
          details.hasAcceptedCardRetentionConsent || await _hasSavedConsent();
      if (isClosed) return;
      if (onDetailsLoaded != null || details.evidence.isNotEmpty) {
        emit(IdentityAccountState(details: details, busy: true, loading: true));
        if (onDetailsLoaded != null) await onDetailsLoaded(hasConsent);
        if (isClosed) return;
      }
      final photos = <String, Uint8List>{};
      await Future.wait(
        details.evidence.entries.map((entry) async {
          try {
            photos[entry.key] = await repository.accountEvidence(entry.value);
          } catch (_) {
            /* รูปที่หมดอายุหรือโหลดไม่ได้ให้เพิ่มใหม่ โดยไม่ทิ้งข้อมูลฟอร์ม */
          }
        }),
      );
      if (!isClosed)
        emit(IdentityAccountState(details: details, photos: photos));
    } catch (error) {
      if (!isClosed)
        emit(
          IdentityAccountState(
            details: state.details,
            photos: state.photos,
            sent: state.sent,
            error: error is IdentityFailure
                ? error.message
                : 'โหลดข้อมูลไม่ได้ กรุณาลองใหม่',
          ),
        );
    }
  }

  Future<bool> _hasSavedConsent() async {
    try {
      return await _consentStore.hasAccepted();
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveConsent() async {
    try {
      return await _consentStore.saveAcceptance();
    } catch (_) {
      return false;
    }
  }

  Future<bool> submit(
    Map<String, String> fields, {
    Uint8List? card,
    Uint8List? selfie,
  }) async {
    if (state.busy || state.sent || state.details?.pending == true)
      return false;
    emit(
      IdentityAccountState(
        details: state.details,
        photos: state.photos,
        busy: true,
      ),
    );
    try {
      await repository.updateAccount(fields, card: card, selfie: selfie);
      if (isClosed) return false;
      emit(
        IdentityAccountState(
          details: state.details,
          photos: {
            ...state.photos,
            if (card != null) 'card': card,
            if (selfie != null) 'selfie': selfie,
          },
          sent: true,
        ),
      );
      return true;
    } catch (error) {
      if (!isClosed)
        emit(
          IdentityAccountState(
            details: state.details,
            photos: state.photos,
            error: error is IdentityFailure
                ? error.message
                : 'ส่งข้อมูลไม่สำเร็จ ข้อมูลที่แก้ไขยังอยู่ กรุณาลองใหม่',
          ),
        );
      return false;
    }
  }

  @override
  Future<void> close() {
    repository.close();
    return super.close();
  }
}
