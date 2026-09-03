import '../entities/payment.dart';
import '../repositories/payment_repository.dart';

class GetPaymentStatusUseCase {
  const GetPaymentStatusUseCase(this.repository);

  final PaymentRepository repository;

  Future<RentalPaymentStatus> execute(int rentalId) =>
      repository.getStatus(rentalId);
}
