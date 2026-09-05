import '../entities/rental_booking.dart';
import '../repositories/rental_management_repository.dart';

// คำอธิบาย: UseCase สำหรับดึงรายการคำขอเช่าและปล่อยเช่า
class GetRentalBookingsUseCase {
  final RentalManagementRepository repository;

  const GetRentalBookingsUseCase(this.repository);

  Future<List<RentalBooking>> executeRenting(String userId) {
    return repository.getRentingBookings(userId);
  }

  Future<List<RentalBooking>> executeLending(String userId) {
    return repository.getLendingBookings(userId);
  }
}
