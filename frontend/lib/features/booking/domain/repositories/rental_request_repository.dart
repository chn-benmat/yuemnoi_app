import '../entities/rental_request.dart';

abstract class RentalRequestRepository {
  Future<RentalRequestResult> submit(RentalRequestDraft draft);

  void close();
}

class RentalRequestException implements Exception {
  const RentalRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}
