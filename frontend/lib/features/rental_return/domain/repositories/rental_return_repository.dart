import '../entities/rental_return_session.dart';

abstract class RentalReturnRepository {
  /// ดึงข้อมูล Session การคืนจาก bookingId หรือรายการเช่าปัจจุบัน
  Future<RentalReturnSession> getReturnSession([int? rentalId]);

  /// อัปโหลดภาพถ่ายตรวจสอบสภาพเครื่องสด
  Future<String> uploadInspectionPhoto({
    required int rentalId,
    required String photoPath,
    required String angleKey,
    required String challengeCode,
  });

  /// บันทึกการส่งมอบผลตรวจสภาพเครื่องสด
  Future<void> submitConditionVerification({
    required int rentalId,
    required List<ReturnInspectionPhoto> photos,
    required Map<String, bool> checklist,
  });

  /// ฝ่ายร้านค้ายืนยันว่าตรวจรับเครื่องเรียบร้อย และสร้าง Dynamic QR
  Future<Map<String, String>> confirmMerchantReceipt({
    required int rentalId,
    required String merchantId,
  });

  /// ฝ่ายผู้เช่าสแกน QR หรือกรอก OTP เพื่อจบกระบวนการคืน
  Future<bool> completeReturnWithToken({
    required int rentalId,
    required String tokenOrOtp,
  });
}
