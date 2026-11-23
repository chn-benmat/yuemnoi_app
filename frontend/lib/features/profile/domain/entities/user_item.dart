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
  final String rentalType;
  final bool ownerHidden;

  const UserItem({
    this.id,
    required this.title,
    required this.subtitle,
    this.price = 0.0,
    this.imageCount = 1,
    this.imageUrl,
    this.category = 'ทั่วไป',
    this.status = '',
    this.rentalType = '',
    this.ownerHidden = false,
  });

  // สถานะประกาศไม่ได้ยืนยันว่าอุปกรณ์ว่างในช่วงวันที่ต้องการเช่า
  UserItemStatus get listingStatus => switch (status.trim().toLowerCase()) {
    'available' || 'พร้อมใช้งาน' || 'พร้อมให้เช่า' => UserItemStatus.available,
    'pending_review' => UserItemStatus.pendingReview,
    'rejected' => UserItemStatus.rejected,
    'rented' || 'renting' || 'กำลังเช่า' || 'ถูกเช่า' => UserItemStatus.rented,
    'unavailable' || 'ไม่พร้อมใช้งาน' => UserItemStatus.unavailable,
    'maintenance' || 'ซ่อมบำรุง' => UserItemStatus.maintenance,
    _ => UserItemStatus.unknown,
  };
}
