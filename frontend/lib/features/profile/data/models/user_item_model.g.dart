// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_item_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserItemModel _$UserItemModelFromJson(Map<String, dynamic> json) =>
    UserItemModel(
      id: (json['id'] as num?)?.toInt(),
      title: UserItemModel._title(json['item_name']),
      subtitle: UserItemModel._readSubtitle(json, 'subtitle') as String,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      imageCount: UserItemModel._readImages(json, 'imageCount') == null
          ? 1
          : UserItemModel._imageCount(
              UserItemModel._readImages(json, 'imageCount'),
            ),
      imageUrl: UserItemModel._extractFirstImageUrl(
        UserItemModel._readImages(json, 'imageUrl'),
      ),
      category: json['category'] == null
          ? 'ทั่วไป'
          : UserItemModel._category(json['category']),
      status: json['status'] as String? ?? '',
      isRentalOccupied: json['is_rental_occupied'] as bool? ?? false,
      rentalType: json['type'] as String? ?? '',
      ownerHidden: json['owner_hidden'] as bool? ?? false,
    );
