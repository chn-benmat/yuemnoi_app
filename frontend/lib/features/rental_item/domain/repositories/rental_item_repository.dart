import '../entities/rental_item.dart';

class RentalItemException implements Exception {
  const RentalItemException(this.message);

  final String message;
}

abstract interface class RentalItemRepository {
  Future<RentalItem> create(RentalItemDraft draft);
  void close();
}
