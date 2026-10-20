import '../entities/item_inquiry_data.dart';

class ShouldSendItemInquiryUseCase {
  const ShouldSendItemInquiryUseCase();

  bool call({
    required ItemInquiryData? latestInquiry,
    required int? latestBookingId,
    required String? latestBookingStatus,
  }) {
    if (latestBookingId == null) return latestInquiry == null;
    const closedStatuses = {
      'completed',
      'cancelled',
      'canceled',
      'finished',
      'rejected',
      'reject',
      'คืนของสำเร็จ',
    };
    if (!closedStatuses.contains(latestBookingStatus?.trim().toLowerCase())) {
      return false;
    }
    // รอบใหม่ส่งได้ครั้งเดียวหลังรายการเดิมปิด แม้ผู้ใช้กลับมาเปิดแชตอีก
    return latestInquiry?.previousBookingId != latestBookingId;
  }
}
