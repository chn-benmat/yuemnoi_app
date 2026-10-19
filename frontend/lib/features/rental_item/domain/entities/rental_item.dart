import 'dart:typed_data';
import '../../../../core/models/pickup_location.dart';

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

class RentalItemPhoto {
  const RentalItemPhoto.remote(String url) : remoteUrl = url, localImage = null;
  const RentalItemPhoto.local(RentalItemImage image)
    : localImage = image,
      remoteUrl = null;

  final String? remoteUrl;
  final RentalItemImage? localImage;
}

class RentalItemDraft {
  const RentalItemDraft({
    required this.name,
    required this.category,
    required this.description,
    required this.rentalType,
    required this.price,
    required this.images,
    this.pickupLocation,
  });

  final String name;
  final String category;
  final String description;
  final String rentalType;
  final int price;
  final List<RentalItemImage> images;
  final PickupLocation? pickupLocation;
}
