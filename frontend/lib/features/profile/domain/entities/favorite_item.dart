// คำอธิบาย: Entity แทนอุปกรณ์ที่ผู้ใช้กดถูกใจ (Wishlist) ในชั้น Domain
class FavoriteItem {
  final int id;
  final String title;
  final String ownerId;
  final String ownerName;
  final String? imageUrl;
  final double price;
  final String category;

  const FavoriteItem({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.ownerName,
    this.imageUrl,
    this.price = 0.0,
    this.category = '',
  });
}
