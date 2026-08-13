import 'dart:typed_data';

class RentalItem {
  const RentalItem({required this.id, required this.imageUrls});

  final int id;
  final List<String> imageUrls;
}

class RentalItemImage {
  const RentalItemImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

class RentalItemDraft {
  const RentalItemDraft({
    required this.name,
    required this.category,
    required this.description,
    required this.rentalType,
    required this.price,
    required this.images,
  });

  final String name;
  final String category;
  final String description;
  final String rentalType;
  final int price;
  final List<RentalItemImage> images;
}
