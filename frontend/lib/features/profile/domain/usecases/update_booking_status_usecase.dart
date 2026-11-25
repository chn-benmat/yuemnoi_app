import '../entities/rental_handover_payment.dart';
import '../repositories/rental_management_repository.dart';

// คำอธิบาย: UseCase สำหรับอัปเดตสถานะการเช่าและยืนยันการรับเงิน
class UpdateBookingStatusUseCase {
  final RentalManagementRepository repository;

  const UpdateBookingStatusUseCase(this.repository);

  Future<RentalHandoverPayment> handoverPayment({
    required int bookingId,
    bool confirm = false,
    String? promptPayPhone,
    String? promptPayNationalId,
  }) {
    final repo = repository;
    if (repo is RentalHandoverRepository) {
      return (repo as RentalHandoverRepository).handoverPayment(
        bookingId: bookingId,
        confirm: confirm,
        promptPayPhone: promptPayPhone,
        promptPayNationalId: promptPayNationalId,
      );
    }
    throw StateError('ระบบตรวจสอบการชำระเงินยังไม่พร้อมใช้งาน');
  }

  Future<void> execute({required int bookingId, required String status}) {
    return repository.updateBookingStatus(bookingId: bookingId, status: status);
  }
}
