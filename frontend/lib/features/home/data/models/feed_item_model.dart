import 'package:json_annotation/json_annotation.dart';

import '../../domain/entities/feed_item.dart';

part 'feed_item_model.g.dart';

/// โมเดลข้อมูลอุปกรณ์ในเลเยอร์ Data
@JsonSerializable(fieldRename: FieldRename.snake)
class FeedItemModel extends FeedItem {
  const FeedItemModel({
    required super.id,
    @JsonKey(readValue: _readTitle, defaultValue: '') required super.title,
    super.description = '',
    @JsonKey(readValue: _readCategoryId, defaultValue: 'all')
    required super.categoryId,
    @JsonKey(readValue: _readRawCategory) super.rawCategory = '',
    @JsonKey(defaultValue: 0) required super.price,
    @JsonKey(defaultValue: '/ วัน') required super.priceUnit,
    @JsonKey(defaultValue: 0.0) required super.rating,
    @JsonKey(defaultValue: 0) required super.reviewCount,
    @JsonKey(defaultValue: 1.0) required super.distanceKm,
    required super.isVerified,
    @JsonKey(defaultValue: 'ผู้ใช้งาน') required super.ownerName,
    super.isOwner = false,
    super.ownerAvatarUrl,
    @JsonKey(readValue: _readImageUrl, defaultValue: '')
    required super.imageUrl,
    super.isCurated = false,
    super.isFavorite = false,
    super.tags = const [],
    super.locationName = 'กรุงเทพฯ',
  });

  // ตัวสร้างโค้ดอ่าน converter จาก getter แต่ไม่อ่านจาก super parameter
  @override
  @JsonKey(fromJson: _string)
  String get id => super.id;

  @override
  @JsonKey(fromJson: _isTrue)
  bool get isVerified => super.isVerified;

  @override
  @JsonKey(fromJson: _tags)
  List<String> get tags => super.tags;

  factory FeedItemModel.fromJson(Map<String, dynamic> json) =>
      _$FeedItemModelFromJson(json);

  Map<String, dynamic> toJson() => _$FeedItemModelToJson(this);

  static Object? _readTitle(Map json, String key) =>
      json[key] as String? ?? json['item_name'] as String?;
  static Object? _readCategoryId(Map json, String key) =>
      json[key] as String? ?? json['category'] as String?;
  static Object? _readRawCategory(Map json, String key) =>
      json[key] as String? ?? json['category'] as String?;
  static Object? _readImageUrl(Map json, String key) =>
      json[key] as String? ?? json['item_image_url'] as String?;
  static String _string(Object? value) => value?.toString() ?? '';
  static bool _isTrue(Object? value) => value == true;
  static List<String> _tags(Object? value) =>
      (value as List<dynamic>?)?.map((tag) => tag.toString()).toList() ??
      const [];

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
    bool? isOwner,
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
      isOwner: isOwner ?? this.isOwner,
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
    isOwner: isOwner,
    ownerAvatarUrl: ownerAvatarUrl,
    imageUrl: imageUrl,
    isCurated: isCurated,
    isFavorite: isFavorite,
    tags: tags,
    locationName: locationName,
  );
}
