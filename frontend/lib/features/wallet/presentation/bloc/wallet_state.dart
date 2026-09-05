import 'package:equatable/equatable.dart';

import '../../domain/entities/wallet_transaction.dart';

enum WalletStatus { initial, loading, success }

class WalletState extends Equatable {
  WalletState({
    this.balance = 1200,
    List<WalletTransaction>? transactions,
    this.status = WalletStatus.initial,
  }) : transactions =
           transactions ??
           [
             WalletTransaction(
               id: 'tx_default_1',
               title: 'โอนเข้าบัญชี',
               amount: 1200,
               dateTime: DateTime(2026, 5, 2, 10, 25),
               status: 'เสร็จสิ้น',
             ),
           ];

  final double balance;
  final List<WalletTransaction> transactions;
  final WalletStatus status;

  WalletState copyWith({
    double? balance,
    List<WalletTransaction>? transactions,
    WalletStatus? status,
  }) {
    return WalletState(
      balance: balance ?? this.balance,
      transactions: transactions ?? this.transactions,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [balance, transactions, status];
}
