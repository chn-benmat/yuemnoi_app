import 'package:equatable/equatable.dart';

class WalletTopUpCheckout extends Equatable {
  const WalletTopUpCheckout({
    required this.sessionId,
    required this.checkoutUrl,
    required this.amount,
  });

  final String sessionId;
  final Uri checkoutUrl;
  final double amount;

  @override
  List<Object?> get props => [sessionId, checkoutUrl, amount];
}
