import '../entities/payment.dart';

class PaymentException implements Exception {
  const PaymentException(this.message);

  final String message;
}

abstract interface class PaymentRepository {
  Future<PaymentCheckout> startCheckout(PaymentRentalDraft draft);
  Future<int> createRental(PaymentRentalDraft draft);
  Future<bool> payWithWallet(int rentalId);
  Future<RentalPaymentStatus> getStatus(int rentalId);
  void close();
}
