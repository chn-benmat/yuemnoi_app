import 'package:equatable/equatable.dart';

/// เอนทิตีแทนอุปกรณ์สำหรับเช่าในหน้า Home Feed
class FeedItem extends Equatable {
  const FeedItem({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.price,
    required this.priceUnit,
    required this.rating,
    required this.reviewCount,
    required this.distanceKm,
    required this.isVerified,
    required this.ownerName,
    this.ownerAvatarUrl,
    required this.imageUrl,
    this.isCurated = false,
    this.isFavorite = false,
    this.tags = const [],
    this.locationName = 'กรุงเทพฯ',
  });

  /// รหัสประจำตัวอุปกรณ์
  final String id;

  /// ชื่ออุปกรณ์
  final String title;

  /// หมวดหมู่อุปกรณ์
  final String categoryId;

  /// ราคาเช่า (บาท)
  final int price;

  /// หน่วยเวลา (เช่น '/ วัน', '/ ชั่วโมง')
  final String priceUnit;

  /// คะแนนรีวิว (เช่น 4.9)
  final double rating;

  /// จำนวนรีวิว
  final int reviewCount;

  /// ระยะทางจากผู้ใช้ (กิโลเมตร)
  final double distanceKm;

  /// สถานะการยืนยันตัวตนของผู้ให้เช่า
  final bool isVerified;

  /// ชื่อเจ้าของอุปกรณ์
  final String ownerName;

  /// รูปโปรไฟล์เจ้าของอุปกรณ์
  final String? ownerAvatarUrl;

  /// URL รูปภาพอุปกรณ์
  final String imageUrl;

  /// เป็นรายการคัดสรรแนะนำพิเศษ (Curated Daily) หรือไม่
  final bool isCurated;

  /// ผู้ใช้บันทึกเป็นรายการโปรดหรือไม่
  final bool isFavorite;

  /// แท็กที่เกี่ยวข้อง
  final List<String> tags;

  /// ชื่อสถานที่หรือพื้นที่
  final String locationName;

  FeedItem copyWith({
    String? id,
    String? title,
    String? categoryId,
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
    return FeedItem(
      id: id ?? this.id,
      title: title ?? this.title,
      categoryId: categoryId ?? this.categoryId,
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

  @override
  List<Object?> get props => [
    id,
    title,
    categoryId,
    price,
    priceUnit,
    rating,
    reviewCount,
    distanceKm,
    isVerified,
    ownerName,
    ownerAvatarUrl,
    imageUrl,
    isCurated,
    isFavorite,
    tags,
    locationName,
  ];
}
