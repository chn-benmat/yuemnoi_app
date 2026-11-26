import 'package:equatable/equatable.dart';

/// เอนทิตีแทนอุปกรณ์สำหรับเช่าในหน้า Home Feed
class FeedItem extends Equatable {
  const FeedItem({
    required this.id,
    required this.title,
    this.description = '',
    required this.categoryId,
    this.rawCategory = '',
    required this.price,
    required this.priceUnit,
    required this.rating,
    required this.reviewCount,
    this.paidBookingCount = 0,
    this.isRentalOccupied = false,
    this.distanceKm,
    required this.isVerified,
    required this.ownerName,
    this.isOwner = false,
    this.ownerAvatarUrl,
    required this.imageUrl,
    this.isCurated = false,
    this.isFavorite = false,
    this.tags = const [],
    this.locationName = 'กรุงเทพฯ',
    this.pickupLatitude,
    this.pickupLongitude,
  });

  /// รหัสประจำตัวอุปกรณ์
  final String id;

  /// ชื่ออุปกรณ์
  final String title;

  /// รายละเอียดหรือคำอธิบายอุปกรณ์
  final String description;

  /// หมวดหมู่อุปกรณ์
  final String categoryId;

  /// ชื่อหมวดหมู่ดั้งเดิมในฐานข้อมูล (เช่น ภาษาไทย)
  final String rawCategory;

  /// ราคาเช่า (บาท)
  final int price;

  /// หน่วยเวลา (เช่น '/ วัน', '/ ชั่วโมง')
  final String priceUnit;

  /// คะแนนรีวิว (เช่น 4.9)
  final double rating;

  /// จำนวนรีวิว
  final int reviewCount;

  /// จำนวนการจองที่ชำระเงินแล้ว
  final int paidBookingCount;

  final bool isRentalOccupied;

  /// ระยะทางจากผู้ใช้ (กิโลเมตร)
  final double? distanceKm;

  /// สถานะการยืนยันตัวตนของผู้ให้เช่า
  final bool isVerified;

  /// ชื่อเจ้าของอุปกรณ์
  final String ownerName;

  /// ใช้เลือกรูปแบบระหว่างโหลด สิทธิ์จัดการยืนยันจากรายละเอียดอุปกรณ์อีกครั้ง
  final bool isOwner;

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
  final double? pickupLatitude;
  final double? pickupLongitude;

  FeedItem copyWith({
    String? id,
    String? title,
    String? description,
    String? categoryId,
    String? rawCategory,
    int? price,
    String? priceUnit,
    double? rating,
    int? reviewCount,
    int? paidBookingCount,
    bool? isRentalOccupied,
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
    return FeedItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      rawCategory: rawCategory ?? this.rawCategory,
      price: price ?? this.price,
      priceUnit: priceUnit ?? this.priceUnit,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      paidBookingCount: paidBookingCount ?? this.paidBookingCount,
      isRentalOccupied: isRentalOccupied ?? this.isRentalOccupied,
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
      pickupLatitude: pickupLatitude,
      pickupLongitude: pickupLongitude,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    categoryId,
    rawCategory,
    price,
    priceUnit,
    rating,
    reviewCount,
    paidBookingCount,
    isRentalOccupied,
    distanceKm,
    isVerified,
    ownerName,
    isOwner,
    ownerAvatarUrl,
    imageUrl,
    isCurated,
    isFavorite,
    tags,
    locationName,
    pickupLatitude,
    pickupLongitude,
  ];
}
