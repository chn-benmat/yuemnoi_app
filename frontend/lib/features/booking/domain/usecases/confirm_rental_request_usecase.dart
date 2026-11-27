import '../entities/rental_request.dart';
import '../repositories/rental_request_repository.dart';

class ConfirmRentalRequestUseCase {
  const ConfirmRentalRequestUseCase(this.repository);

  final RentalRequestRepository repository;

  Future<RentalRequestResult> execute({
    required int rentalId,
    required String offerMessageId,
    required String paymentMethod,
  }) async {
    if (rentalId <= 0 || offerMessageId.trim().isEmpty) {
      throw const RentalRequestException('ไม่พบข้อเสนอที่ต้องการยืนยัน');
    }
    final result = await repository.confirm(
      rentalId: rentalId,
      offerMessageId: offerMessageId,
      paymentMethod: paymentMethod,
    );
    if (result.id != rentalId ||
        !const [
          'confirmed',
          'active',
          'awaiting_return',
          'return_ready',
          'completed',
        ].contains(result.status)) {
      throw const RentalRequestException(
        'ระบบยังไม่ยืนยันการเช่า กรุณาลองใหม่',
      );
    }
    return result;
  }
}
