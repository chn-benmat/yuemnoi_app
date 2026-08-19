import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/wallet_transaction.dart';
import 'wallet_state.dart';

class WalletCubit extends Cubit<WalletState> {
  WalletCubit()
      : super(
          WalletState(
            balance: 1200.00,
            transactions: [
              WalletTransaction(
                id: 'tx_default_1',
                title: 'โอนเข้าบัญชี',
                amount: 1200.00,
                dateTime: DateTime(2026, 5, 2, 10, 25),
                status: 'เสร็จสิ้น',
              ),
            ],
          ),
        );

  Future<void> topUp({
    required double amount,
    String paymentMethod = 'ธนาคาร',
  }) async {
    emit(state.copyWith(status: WalletStatus.loading));

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 600));

    final newTransaction = WalletTransaction(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      title: 'โอนเข้าบัญชี',
      amount: amount,
      dateTime: DateTime.now(),
      status: 'เสร็จสิ้น',
    );

    final updatedTransactions = [newTransaction, ...state.transactions];
    final updatedBalance = state.balance + amount;

    emit(
      state.copyWith(
        balance: updatedBalance,
        transactions: updatedTransactions,
        status: WalletStatus.success,
      ),
    );
  }
}
