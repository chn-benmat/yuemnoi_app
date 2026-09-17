import '../entities/rental_request.dart';
import '../repositories/rental_request_repository.dart';

class SubmitRentalRequestUseCase {
  const SubmitRentalRequestUseCase(this.repository);

  final RentalRequestRepository repository;

  Future<RentalRequestResult> execute(RentalRequestDraft draft) {
    return repository.submit(draft);
  }
}
