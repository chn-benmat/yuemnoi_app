import '../entities/rental_handover_code.dart';
import '../repositories/rental_management_repository.dart';

// คำอธิบาย: UseCase สำหรับอัปเดตสถานะการเช่าและยืนยันการส่งมอบ
class UpdateBookingStatusUseCase {
  final RentalManagementRepository repository;

  const UpdateBookingStatusUseCase(this.repository);

  Future<RentalHandoverCode> createHandoverCode({required int bookingId}) {
    if (repository is RentalHandoverRepository) {
      return (repository as RentalHandoverRepository).createHandoverCode(
        bookingId: bookingId,
      );
    }
    throw StateError('ระบบสร้างรหัสส่งมอบยังไม่พร้อมใช้งาน');
  }

  Future<void> completeHandover({
    required int bookingId,
    required String code,
  }) {
    if (repository is RentalHandoverRepository) {
      return (repository as RentalHandoverRepository).completeHandover(
        bookingId: bookingId,
        code: code,
      );
    }
    throw StateError('ระบบยืนยันส่งมอบยังไม่พร้อมใช้งาน');
  }

  Future<void> execute({required int bookingId, required String status}) {
    return repository.updateBookingStatus(bookingId: bookingId, status: status);
  }
}
