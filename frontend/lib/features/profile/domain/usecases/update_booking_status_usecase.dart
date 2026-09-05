import '../repositories/rental_management_repository.dart';

// คำอธิบาย: UseCase สำหรับอัปเดตสถานะการเช่า (เช่น active, completed)
class UpdateBookingStatusUseCase {
  final RentalManagementRepository repository;

  const UpdateBookingStatusUseCase(this.repository);

  Future<void> execute({
    required int bookingId,
    required String status,
  }) {
    return repository.updateBookingStatus(
      bookingId: bookingId,
      status: status,
    );
  }
}
