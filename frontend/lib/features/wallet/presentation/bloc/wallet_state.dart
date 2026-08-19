import 'package:equatable/equatable.dart';
import '../../domain/entities/wallet_transaction.dart';

enum WalletStatus { initial, loading, success, failure }

class WalletState extends Equatable {
  final double balance;
  final List<WalletTransaction> transactions;
  final WalletStatus status;
  final String? errorMessage;

  const WalletState({
    this.balance = 1200.00,
    this.transactions = const [],
    this.status = WalletStatus.initial,
    this.errorMessage,
  });

  WalletState copyWith({
    double? balance,
    List<WalletTransaction>? transactions,
    WalletStatus? status,
    String? errorMessage,
  }) {
    return WalletState(
      balance: balance ?? this.balance,
      transactions: transactions ?? this.transactions,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [balance, transactions, status, errorMessage];
}
