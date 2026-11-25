class RentalHandoverPayment {
  const RentalHandoverPayment({
    required this.status,
    required this.paymentMethod,
    required this.paymentConfirmed,
    this.totalSatang,
    this.canCollectPayment = false,
    this.promptPayPhone,
    this.promptPayIdType,
    this.promptPayQr,
  });

  final String status;
  final String paymentMethod;
  final bool paymentConfirmed;
  final int? totalSatang;
  final bool canCollectPayment;
  final String? promptPayPhone;
  final String? promptPayIdType;
  final String? promptPayQr;
}
