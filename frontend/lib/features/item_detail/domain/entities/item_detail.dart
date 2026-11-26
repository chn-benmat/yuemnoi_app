import 'package:equatable/equatable.dart';
import '../../../../core/models/pickup_location.dart';

import '../../../rental_item/domain/entities/rental_item.dart';

class ItemOwner extends Equatable {
  const ItemOwner({
    required this.userId,
    required this.displayName,
    required this.imageUrl,
    this.isVerified = false,
  });

  final String userId;
  final String displayName;
  final String imageUrl;
  final bool isVerified;

  @override
  List<Object?> get props => [userId, displayName, imageUrl, isVerified];
}

class ItemReview extends Equatable {
  const ItemReview({
    required this.id,
    required this.reviewer,
    required this.rating,
    required this.description,
  });

  final int id;
  final ItemOwner reviewer;
  final double rating;
  final String description;

  @override
  List<Object?> get props => [id, reviewer, rating, description];
}

class ItemDetail extends Equatable {
  const ItemDetail({
    required this.id,
    required this.owner,
    required this.name,
    required this.imageUrls,
    required this.description,
    required this.category,
    required this.price,
    this.additionalDailyPrice,
    required this.status,
    this.isRentalOccupied = false,
    this.isRentalQueueHeld = false,
    required this.rentalType,
    required this.reviews,
    required this.isOwner,
    this.ownerHidden = false,
    this.pickupLocation,
  });

  final int id;
  final ItemOwner owner;
  final String name;
  final List<String> imageUrls;
  final String description;
  final String category;
  final int price;
  final int? additionalDailyPrice;
  final String status;
  final bool isRentalOccupied;
  final bool isRentalQueueHeld;
  final String rentalType;
  final List<ItemReview> reviews;
  final bool isOwner;
  final bool ownerHidden;
  final PickupLocation? pickupLocation;

  bool get _isHourly => rentalType == 'รายชั่วโมง';
  String get unitLabel => _isHourly ? 'ชั่วโมง' : 'วัน';
  int? get hourlyPrice => _isHourly ? price : null;
  int? get dailyPrice => _isHourly ? additionalDailyPrice : price;

  ItemDetail withVisibility({required bool hidden}) => ItemDetail(
    id: id,
    owner: owner,
    name: name,
    imageUrls: imageUrls,
    description: description,
    category: category,
    price: price,
    additionalDailyPrice: additionalDailyPrice,
    status: status,
    isRentalOccupied: isRentalOccupied,
    isRentalQueueHeld: isRentalQueueHeld,
    rentalType: rentalType,
    reviews: reviews,
    isOwner: isOwner,
    ownerHidden: hidden,
    pickupLocation: pickupLocation,
  );

  double get averageRating {
    if (reviews.isEmpty) return 0;
    return reviews.fold<double>(0, (sum, review) => sum + review.rating) /
        reviews.length;
  }

  @override
  List<Object?> get props => [
    id,
    owner,
    name,
    imageUrls,
    description,
    category,
    price,
    additionalDailyPrice,
    status,
    isRentalOccupied,
    isRentalQueueHeld,
    rentalType,
    reviews,
    isOwner,
    ownerHidden,
    pickupLocation,
  ];
}

class ItemEditDraft extends Equatable {
  const ItemEditDraft({
    required this.itemId,
    required this.name,
    required this.category,
    required this.description,
    required this.rentalType,
    required this.price,
    this.additionalDailyPrice,
    required this.retainedImageUrls,
    required this.newImages,
    this.imageOrder,
    this.pickupLocation,
  });

  final int itemId;
  final String name;
  final String category;
  final String description;
  final String rentalType;
  final int price;
  final int? additionalDailyPrice;
  final List<String> retainedImageUrls;
  final List<RentalItemImage> newImages;
  final List<RentalItemPhoto>? imageOrder;
  final PickupLocation? pickupLocation;

  List<String> resolveImageUrls(List<String> uploadedUrls) {
    if (uploadedUrls.length != newImages.length) {
      throw const FormatException('จำนวนรูปที่อัปโหลดไม่ครบ');
    }
    final order = imageOrder;
    if (order == null) return [...retainedImageUrls, ...uploadedUrls];
    final remainingRemote = [...retainedImageUrls];
    final remainingLocal = [...newImages];
    final urls = <String>[];
    for (final photo in order) {
      if (photo.remoteUrl case final url?) {
        if (!remainingRemote.remove(url)) {
          throw const FormatException('ลำดับรูปภาพไม่ถูกต้อง');
        }
        urls.add(url);
      } else {
        final image = photo.localImage;
        if (!remainingLocal.remove(image)) {
          throw const FormatException('ลำดับรูปภาพไม่ถูกต้อง');
        }
        urls.add(uploadedUrls[newImages.indexOf(image!)]);
      }
    }
    if (remainingRemote.isNotEmpty || remainingLocal.isNotEmpty) {
      throw const FormatException('ลำดับรูปภาพไม่ครบ');
    }
    return urls;
  }

  @override
  List<Object?> get props => [
    itemId,
    name,
    category,
    description,
    rentalType,
    price,
    additionalDailyPrice,
    retainedImageUrls,
    newImages,
    imageOrder,
    pickupLocation,
  ];
}
