import 'package:equatable/equatable.dart';
import '../../domain/entities/wallet_transaction.dart';

enum WalletStatus { initial, loading, success, failure }

class WalletState extends Equatable {
  final double balance;
  final String currency;
  final List<WalletTransaction> transactions;
  final WalletStatus status;
  final Uri? topUpCheckoutUrl;
  final String? errorMessage;

  WalletState({
    this.balance = 1200.00,
    this.currency = 'THB',
    List<WalletTransaction>? transactions,
    this.status = WalletStatus.initial,
    this.topUpCheckoutUrl,
    this.errorMessage,
  }) : transactions = transactions ??
            [
              WalletTransaction(
                id: 'tx_default_1',
                title: 'โอนเข้าบัญชี',
                amount: 1200.00,
                dateTime: DateTime(2026, 5, 2, 10, 25),
                status: 'เสร็จสิ้น',
              ),
            ];

  WalletState copyWith({
    double? balance,
    String? currency,
    List<WalletTransaction>? transactions,
    WalletStatus? status,
    Uri? topUpCheckoutUrl,
    String? errorMessage,
    bool clearCheckoutUrl = false,
    bool clearError = false,
  }) {
    return WalletState(
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      transactions: transactions ?? this.transactions,
      status: status ?? this.status,
      topUpCheckoutUrl: clearCheckoutUrl ? null : (topUpCheckoutUrl ?? this.topUpCheckoutUrl),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        balance,
        currency,
        transactions,
        status,
        topUpCheckoutUrl,
        errorMessage,
      ];
}
