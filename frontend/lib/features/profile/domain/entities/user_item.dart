enum UserItemStatus {
  available,
  pendingReview,
  rejected,
  rented,
  unavailable,
  maintenance,
  unknown,
}

// คำอธิบาย: Entity แทนรายการอุปกรณ์ของผู้ใช้ในชั้น Domain
class UserItem {
  final int? id;
  final String title;
  final String subtitle;
  final double price;
  final int imageCount;
  final String? imageUrl;
  final String category;
  final String status;
  final bool isRentalOccupied;
  final String rentalType;
  final bool ownerHidden;
  final bool moderationHidden;

  const UserItem({
    this.id,
    required this.title,
    required this.subtitle,
    this.price = 0.0,
    this.imageCount = 1,
    this.imageUrl,
    this.category = 'ทั่วไป',
    this.status = '',
    this.isRentalOccupied = false,
    this.rentalType = '',
    this.ownerHidden = false,
    this.moderationHidden = false,
  });

  bool get hiddenByModeration =>
      moderationHidden &&
      listingStatus != UserItemStatus.pendingReview &&
      listingStatus != UserItemStatus.rejected;
  bool get isHidden => ownerHidden || hiddenByModeration;

  // ใช้ข้อมูลการจองที่ยืนยันแล้วเป็นเกณฑ์แสดงสถานะกำลังถูกเช่า
  UserItemStatus get listingStatus => switch (status.trim().toLowerCase()) {
    'pending_review' => UserItemStatus.pendingReview,
    'rejected' => UserItemStatus.rejected,
    _ when isRentalOccupied => UserItemStatus.rented,
    'available' || 'พร้อมใช้งาน' || 'พร้อมให้เช่า' => UserItemStatus.available,
    'rented' ||
    'renting' ||
    'กำลังเช่า' ||
    'ถูกเช่า' ||
    'กำลังถูกเช่า' ||
    'unavailable' ||
    'ไม่พร้อมใช้งาน' => UserItemStatus.unavailable,
    'maintenance' || 'ซ่อมบำรุง' => UserItemStatus.maintenance,
    _ => UserItemStatus.unknown,
  };
}
