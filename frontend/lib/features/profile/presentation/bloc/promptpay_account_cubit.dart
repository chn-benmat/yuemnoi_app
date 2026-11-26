import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/promptpay_account_repository.dart';
import '../../domain/entities/promptpay_account.dart';

class PromptPayAccountState {
  const PromptPayAccountState({
    this.account,
    this.busy = false,
    this.saved = false,
    this.error,
  });

  final PromptPayAccount? account;
  final bool busy;
  final bool saved;
  final String? error;
}

class PromptPayAccountCubit extends Cubit<PromptPayAccountState> {
  PromptPayAccountCubit(this._repository)
    : super(const PromptPayAccountState());

  final PromptPayAccountRepository _repository;

  Future<void> load() async {
    if (state.busy || state.account != null) return;
    emit(const PromptPayAccountState(busy: true));
    try {
      final account = await _repository.load();
      if (!isClosed) emit(PromptPayAccountState(account: account));
    } catch (error) {
      if (isClosed) return;
      emit(
        PromptPayAccountState(
          error: error is PromptPayAccountException
              ? error.message
              : 'โหลดข้อมูลพร้อมเพย์ไม่สำเร็จ กรุณาลองใหม่',
        ),
      );
    }
  }

  Future<void> save(String identifier, {required bool nationalId}) async {
    final current = state.account;
    if (state.busy || current == null) return;
    emit(PromptPayAccountState(account: current, busy: true));
    try {
      final account = await _repository.save(
        identifier,
        nationalId: nationalId,
      );
      if (!isClosed) emit(PromptPayAccountState(account: account, saved: true));
    } catch (error) {
      if (isClosed) return;
      emit(
        PromptPayAccountState(
          account: current,
          error: error is PromptPayAccountException
              ? error.message
              : 'บันทึกพร้อมเพย์ไม่สำเร็จ กรุณาลองใหม่',
        ),
      );
    }
  }

  void clearSaveError() {
    if (state.account != null && state.error != null) {
      emit(PromptPayAccountState(account: state.account));
    }
  }

  @override
  Future<void> close() {
    _repository.close();
    return super.close();
  }
}
