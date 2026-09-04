import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/wallet_transaction.dart';
import 'wallet_state.dart';

class WalletCubit extends Cubit<WalletState> {
  WalletCubit() : super(WalletState());

  Future<void> fetchWallet() async {
    // Wallet is intentionally local mock data until a new payment provider is
    // selected. Keep refresh deterministic and free of network side effects.
    emit(state.copyWith(status: WalletStatus.success));
  }

  Future<void> topUp({
    required double amount,
    String paymentMethod = 'จำลอง',
  }) async {
    if (amount <= 0 || state.status == WalletStatus.loading) return;
    emit(state.copyWith(status: WalletStatus.loading));
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final transaction = WalletTransaction(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      title: 'เติมเงินจำลอง',
      amount: amount,
      dateTime: DateTime.now(),
      status: 'เสร็จสิ้น',
    );
    emit(
      state.copyWith(
        balance: state.balance + amount,
        transactions: [transaction, ...state.transactions],
        status: WalletStatus.success,
      ),
    );
  }
}
