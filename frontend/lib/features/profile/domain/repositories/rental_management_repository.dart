import '../entities/rental_booking.dart';
import '../entities/rental_income.dart';

// คำอธิบาย: สัญญา (Contract) การทำงานเกี่ยวกับการจัดการสถานะการเช่า, ส่งมอบ, คืนของ, ประวัติ และรายได้
abstract class RentalManagementRepository {
  Future<List<RentalBooking>> getRentingBookings(String userId);
  Future<List<RentalBooking>> getLendingBookings(String userId);
  Future<List<RentalBooking>> getRentalHistory(String userId);
  Future<void> updateBookingStatus({required int bookingId, required String status});
  Future<RentalIncomeSummary> getRentalIncome(String userId);
}
