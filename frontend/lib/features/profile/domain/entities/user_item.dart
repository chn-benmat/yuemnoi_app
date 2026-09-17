// คำอธิบาย: Entity แทนรายการอุปกรณ์ของผู้ใช้ในชั้น Domain
class UserItem {
  final int? id;
  final String title;
  final String subtitle;
  final double price;
  final int imageCount;
  final String? imageUrl;
  final String category;

  const UserItem({
    this.id,
    required this.title,
    required this.subtitle,
    this.price = 0.0,
    this.imageCount = 1,
    this.imageUrl,
    this.category = 'ทั่วไป',
  });
}
