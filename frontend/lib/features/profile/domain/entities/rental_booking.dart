// คำอธิบาย: Entity แทนข้อมูลรายการเช่า/ปล่อยเช่าในชั้น Domain
class RentalBooking {
  final int? bookingId;
  final int? itemId;
  final String title;
  final String partnerName;
  final String? partnerPhone;
  final String partnerRole;
  final String status;
  final String statusCode;
  final String? category;
  final String? imageUrl;
  final DateTime? startDate;
  final DateTime? endDate;
  final String duration;
  final double totalPrice;
  final String? pickupLocation;
  final bool isOwner;

  const RentalBooking({
    this.bookingId,
    this.itemId,
    required this.title,
    required this.partnerName,
    this.partnerPhone,
    required this.partnerRole,
    required this.status,
    required this.statusCode,
    this.category,
    this.imageUrl,
    this.startDate,
    this.endDate,
    this.duration = '',
    this.totalPrice = 0.0,
    this.pickupLocation,
    this.isOwner = false,
  });
}
