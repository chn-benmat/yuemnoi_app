import '../entities/rental_return_session.dart';

abstract class RentalReturnRepository {
  /// ดึงข้อมูล Session การคืนจาก bookingId หรือรายการเช่าปัจจุบัน
  Future<RentalReturnSession> getReturnSession([int? rentalId]);

  /// ร้านค้ายืนยันว่าตรวจรับเครื่องเรียบร้อยและจบรายการคืน
  Future<void> confirmMerchantReceipt({
    required int rentalId,
    bool pauseItem = false,
  });

  Future<RentalReturnPenaltyReport> savePenaltyReport({
    required int rentalId,
    required bool damaged,
    required bool late,
    required String details,
  });

  Future<String> getPenaltyQr(int rentalId);
}
