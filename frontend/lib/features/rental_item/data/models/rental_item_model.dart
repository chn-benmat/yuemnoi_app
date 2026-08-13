import '../../domain/entities/rental_item.dart';

class RentalItemModel {
  const RentalItemModel({required this.id, required this.imageUrls});

  factory RentalItemModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! num) throw const FormatException('Invalid item id');

    final rawUrls = json['item_image_url'];
    final urls = rawUrls is List
        ? rawUrls.whereType<String>().toList(growable: false)
        : const <String>[];
    return RentalItemModel(id: id.toInt(), imageUrls: urls);
  }

  final int id;
  final List<String> imageUrls;

  RentalItem toEntity() => RentalItem(id: id, imageUrls: imageUrls);
}
