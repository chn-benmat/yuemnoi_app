// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feed_item_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FeedItemModel _$FeedItemModelFromJson(Map<String, dynamic> json) =>
    FeedItemModel(
      id: FeedItemModel._string(json['id']),
      title: FeedItemModel._readTitle(json, 'title') as String? ?? '',
      description: json['description'] as String? ?? '',
      categoryId:
          FeedItemModel._readCategoryId(json, 'category_id') as String? ??
          'all',
      rawCategory:
          FeedItemModel._readRawCategory(json, 'raw_category') as String? ?? '',
      price: (json['price'] as num?)?.toInt() ?? 0,
      priceUnit: json['price_unit'] as String? ?? '/ วัน',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      isVerified: FeedItemModel._isTrue(json['is_verified']),
      ownerName: json['owner_name'] as String? ?? 'ผู้ใช้งาน',
      isOwner: json['is_owner'] as bool? ?? false,
      ownerAvatarUrl: json['owner_avatar_url'] as String?,
      imageUrl: FeedItemModel._readImageUrl(json, 'image_url') as String? ?? '',
      isCurated: json['is_curated'] as bool? ?? false,
      isFavorite: json['is_favorite'] as bool? ?? false,
      tags: json['tags'] == null ? const [] : FeedItemModel._tags(json['tags']),
      locationName: json['location_name'] as String? ?? 'ไม่ระบุตำแหน่ง',
      pickupLatitude: (json['pickup_latitude'] as num?)?.toDouble(),
      pickupLongitude: (json['pickup_longitude'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$FeedItemModelToJson(FeedItemModel instance) =>
    <String, dynamic>{
      'title': instance.title,
      'description': instance.description,
      'category_id': instance.categoryId,
      'raw_category': instance.rawCategory,
      'price': instance.price,
      'price_unit': instance.priceUnit,
      'rating': instance.rating,
      'review_count': instance.reviewCount,
      'owner_name': instance.ownerName,
      'is_owner': instance.isOwner,
      'owner_avatar_url': instance.ownerAvatarUrl,
      'image_url': instance.imageUrl,
      'is_curated': instance.isCurated,
      'is_favorite': instance.isFavorite,
      'location_name': instance.locationName,
      'pickup_latitude': instance.pickupLatitude,
      'pickup_longitude': instance.pickupLongitude,
      'id': instance.id,
      'is_verified': instance.isVerified,
      'tags': instance.tags,
    };
