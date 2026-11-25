// คำอธิบาย: Entity แทนข้อมูลรายการเช่า/ปล่อยเช่าในชั้น Domain
class RentalBooking {
  final int? bookingId;
  final int? itemId;
  final String title;
  final String? partnerId;
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
  final double? latitude;
  final double? longitude;
  final String? pickupNote;
  final bool isOwner;

  const RentalBooking({
    this.bookingId,
    this.itemId,
    required this.title,
    this.partnerId,
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
    this.latitude,
    this.longitude,
    this.pickupNote,
    this.isOwner = false,
  });
}
