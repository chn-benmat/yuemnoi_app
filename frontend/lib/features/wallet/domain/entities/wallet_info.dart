import 'package:equatable/equatable.dart';
import 'wallet_transaction.dart';

class WalletInfo extends Equatable {
  const WalletInfo({
    required this.balance,
    this.currency = 'THB',
    this.transactions = const [],
  });

  final double balance;
  final String currency;
  final List<WalletTransaction> transactions;

  @override
  List<Object?> get props => [balance, currency, transactions];
}
