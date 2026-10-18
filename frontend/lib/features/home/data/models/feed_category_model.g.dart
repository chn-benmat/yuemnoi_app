// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feed_category_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FeedCategoryModel _$FeedCategoryModelFromJson(Map<String, dynamic> json) =>
    FeedCategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      iconName: json['icon_name'] as String?,
    );

Map<String, dynamic> _$FeedCategoryModelToJson(FeedCategoryModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'icon_name': instance.iconName,
    };
