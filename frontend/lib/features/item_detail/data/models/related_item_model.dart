import '../../domain/entities/related_item.dart';

abstract final class RelatedItemModel {
  static RelatedItem fromJson(Map<String, dynamic> json) {
    final id = int.tryParse('${json['id']}');
    final price = int.tryParse('${json['price']}');
    final name = '${json['item_name'] ?? ''}'.trim();
    final category = '${json['category'] ?? ''}'.trim();
    if (id == null ||
        id <= 0 ||
        price == null ||
        price <= 0 ||
        name.isEmpty ||
        category.isEmpty) {
      throw const FormatException('ข้อมูลสินค้าไม่ครบ');
    }
    final images = json['item_image_url'];
    final urls = images is List ? images : [images];
    final imageUrl =
        urls.whereType<String>().where((url) {
          final uri = Uri.tryParse(url);
          return uri != null &&
              uri.host.isNotEmpty &&
              (uri.scheme == 'https' || uri.scheme == 'http');
        }).firstOrNull ??
        '';
    final type = '${json['type'] ?? ''}'.trim().toLowerCase();
    final rentalType = switch (type) {
      'รายชั่วโมง' || 'hour' || 'hourly' => 'รายชั่วโมง',
      'รายวัน' || 'day' || 'daily' => 'รายวัน',
      _ => throw const FormatException('ไม่ระบุหน่วยค่าเช่า'),
    };
    return RelatedItem(
      id: id,
      name: name,
      category: category,
      price: price,
      rentalType: rentalType,
      imageUrl: imageUrl,
    );
  }
}
