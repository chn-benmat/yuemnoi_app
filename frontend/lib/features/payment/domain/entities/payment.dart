import 'package:equatable/equatable.dart';

class PaymentRentalDraft extends Equatable {
  const PaymentRentalDraft({
    required this.itemId,
    required this.startAt,
    required this.endAt,
    required this.rentalType,
    required this.pickupLocation,
  });

  final int itemId;
  final DateTime startAt;
  final DateTime endAt;
  final String rentalType;
  final String pickupLocation;

  @override
  List<Object?> get props => [
    itemId,
    startAt,
    endAt,
    rentalType,
    pickupLocation,
  ];
}

class PaymentCheckout extends Equatable {
  const PaymentCheckout({
    required this.rentalId,
    required this.paymentOrderId,
    required this.checkoutUrl,
    required this.status,
  });

  final int rentalId;
  final String paymentOrderId;
  final Uri checkoutUrl;
  final String status;

  @override
  List<Object?> get props => [rentalId, paymentOrderId, checkoutUrl, status];
}

class RentalPaymentStatus extends Equatable {
  const RentalPaymentStatus({
    required this.rentalId,
    required this.paymentOrderId,
    required this.status,
    required this.amountSatang,
    required this.currency,
    this.paidAt,
  });

  final int rentalId;
  final String paymentOrderId;
  final String status;
  final int amountSatang;
  final String currency;
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';
  bool get isTerminalFailure =>
      status == 'failed' || status == 'expired' || status == 'cancelled';

  @override
  List<Object?> get props => [
    rentalId,
    paymentOrderId,
    status,
    amountSatang,
    currency,
    paidAt,
  ];
}
