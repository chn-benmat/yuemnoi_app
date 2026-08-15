import 'package:equatable/equatable.dart';

import '../../../rental_item/domain/entities/rental_item.dart';

class ItemOwner extends Equatable {
  const ItemOwner({
    required this.userId,
    required this.displayName,
    required this.imageUrl,
  });

  final String userId;
  final String displayName;
  final String imageUrl;

  @override
  List<Object?> get props => [userId, displayName, imageUrl];
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
    required this.status,
    required this.rentalType,
    required this.reviews,
    required this.isOwner,
  });

  final int id;
  final ItemOwner owner;
  final String name;
  final List<String> imageUrls;
  final String description;
  final String category;
  final int price;
  final String status;
  final String rentalType;
  final List<ItemReview> reviews;
  final bool isOwner;

  String get unitLabel => rentalType == 'รายชั่วโมง' ? 'ชั่วโมง' : 'วัน';

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
    status,
    rentalType,
    reviews,
    isOwner,
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
    required this.retainedImageUrls,
    required this.newImages,
  });

  final int itemId;
  final String name;
  final String category;
  final String description;
  final String rentalType;
  final int price;
  final List<String> retainedImageUrls;
  final List<RentalItemImage> newImages;

  @override
  List<Object?> get props => [
    itemId,
    name,
    category,
    description,
    rentalType,
    price,
    retainedImageUrls,
    newImages,
  ];
}
