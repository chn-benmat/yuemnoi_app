import '../entities/payment.dart';
import '../repositories/payment_repository.dart';

class StartPaymentUseCase {
  const StartPaymentUseCase(this.repository);

  final PaymentRepository repository;

  Future<PaymentCheckout> execute(PaymentRentalDraft draft) =>
      repository.startCheckout(draft);
}
