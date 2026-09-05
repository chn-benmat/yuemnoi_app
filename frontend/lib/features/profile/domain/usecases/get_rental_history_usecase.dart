import '../entities/rental_booking.dart';
import '../repositories/rental_management_repository.dart';

// คำอธิบาย: UseCase สำหรับดึงประวัติการเช่าทั้งหมดของผู้ใช้
class GetRentalHistoryUseCase {
  final RentalManagementRepository repository;

  const GetRentalHistoryUseCase(this.repository);

  Future<List<RentalBooking>> execute(String userId) {
    return repository.getRentalHistory(userId);
  }
}
