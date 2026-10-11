import '../../domain/entities/feed_item.dart';

/// โมเดลข้อมูลอุปกรณ์ในเลเยอร์ Data
class FeedItemModel extends FeedItem {
  const FeedItemModel({
    required super.id,
    required super.title,
    super.description = '',
    required super.categoryId,
    super.rawCategory = '',
    required super.price,
    required super.priceUnit,
    required super.rating,
    required super.reviewCount,
    required super.distanceKm,
    required super.isVerified,
    required super.ownerName,
    super.ownerAvatarUrl,
    required super.imageUrl,
    super.isCurated = false,
    super.isFavorite = false,
    super.tags = const [],
    super.locationName = 'กรุงเทพฯ',
  });

  factory FeedItemModel.fromJson(Map<String, dynamic> json) {
    return FeedItemModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? json['item_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      categoryId:
          json['category_id'] as String? ??
          json['category'] as String? ??
          'all',
      rawCategory:
          json['raw_category'] as String? ?? json['category'] as String? ?? '',
      price: (json['price'] as num?)?.toInt() ?? 0,
      priceUnit: json['price_unit'] as String? ?? '/ วัน',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 1.0,
      isVerified: json['is_verified'] == true,
      ownerName: json['owner_name'] as String? ?? 'ผู้ใช้งาน',
      ownerAvatarUrl: json['owner_avatar_url'] as String?,
      imageUrl:
          json['image_url'] as String? ??
          json['item_image_url'] as String? ??
          '',
      isCurated: json['is_curated'] as bool? ?? false,
      isFavorite: json['is_favorite'] as bool? ?? false,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      locationName: json['location_name'] as String? ?? 'กรุงเทพฯ',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category_id': categoryId,
      'raw_category': rawCategory,
      'price': price,
      'price_unit': priceUnit,
      'rating': rating,
      'review_count': reviewCount,
      'distance_km': distanceKm,
      'is_verified': isVerified,
      'owner_name': ownerName,
      'owner_avatar_url': ownerAvatarUrl,
      'image_url': imageUrl,
      'is_curated': isCurated,
      'is_favorite': isFavorite,
      'tags': tags,
      'location_name': locationName,
    };
  }

  @override
  FeedItemModel copyWith({
    String? id,
    String? title,
    String? description,
    String? categoryId,
    String? rawCategory,
    int? price,
    String? priceUnit,
    double? rating,
    int? reviewCount,
    double? distanceKm,
    bool? isVerified,
    String? ownerName,
    String? ownerAvatarUrl,
    String? imageUrl,
    bool? isCurated,
    bool? isFavorite,
    List<String>? tags,
    String? locationName,
  }) {
    return FeedItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      rawCategory: rawCategory ?? this.rawCategory,
      price: price ?? this.price,
      priceUnit: priceUnit ?? this.priceUnit,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      distanceKm: distanceKm ?? this.distanceKm,
      isVerified: isVerified ?? this.isVerified,
      ownerName: ownerName ?? this.ownerName,
      ownerAvatarUrl: ownerAvatarUrl ?? this.ownerAvatarUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      isCurated: isCurated ?? this.isCurated,
      isFavorite: isFavorite ?? this.isFavorite,
      tags: tags ?? this.tags,
      locationName: locationName ?? this.locationName,
    );
  }

  FeedItem toEntity() => FeedItem(
    id: id,
    title: title,
    description: description,
    categoryId: categoryId,
    rawCategory: rawCategory,
    price: price,
    priceUnit: priceUnit,
    rating: rating,
    reviewCount: reviewCount,
    distanceKm: distanceKm,
    isVerified: isVerified,
    ownerName: ownerName,
    ownerAvatarUrl: ownerAvatarUrl,
    imageUrl: imageUrl,
    isCurated: isCurated,
    isFavorite: isFavorite,
    tags: tags,
    locationName: locationName,
  );
}
