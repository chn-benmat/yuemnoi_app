import '../entities/rental_request.dart';

abstract class RentalRequestRepository {
  Future<RentalRequestResult> submit(RentalRequestDraft draft);

  Future<RentalRequestResult> confirm({
    required int rentalId,
    required String offerMessageId,
    required String paymentMethod,
  });

  void close();
}

class RentalRequestException implements Exception {
  const RentalRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}
