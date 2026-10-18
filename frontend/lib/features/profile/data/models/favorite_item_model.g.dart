// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_item_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoriteItemModel _$FavoriteItemModelFromJson(Map<String, dynamic> json) =>
    FavoriteItemModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: FavoriteItemModel._title(json['item_name']),
      ownerId: FavoriteItemModel._string(json['user_id']),
      ownerName: json['_owner_name'] as String? ?? 'เจ้าของอุปกรณ์',
      imageUrl: FavoriteItemModel._extractFirstImageUrl(json['item_image_url']),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      category: json['category'] == null
          ? ''
          : FavoriteItemModel._string(json['category']),
    );
