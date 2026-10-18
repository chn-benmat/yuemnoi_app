// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_request_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BookingItemInfo _$BookingItemInfoFromJson(Map<String, dynamic> json) =>
    BookingItemInfo(
      id: (json['id'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? 'อุปกรณ์เช่า',
      imageUrl: json['imageUrl'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      hourlyRate: (json['hourlyRate'] as num?)?.toDouble() ?? 100.0,
      dailyRate: (json['dailyRate'] as num?)?.toDouble() ?? 500.0,
      defaultLocation: json['defaultLocation'] as String? ?? 'นัดรับตามตกลง',
      ownerName: json['ownerName'] as String? ?? 'ผู้ปล่อยเช่า',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$BookingItemInfoToJson(BookingItemInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'imageUrl': instance.imageUrl,
      'rating': instance.rating,
      'reviewCount': instance.reviewCount,
      'hourlyRate': instance.hourlyRate,
      'dailyRate': instance.dailyRate,
      'defaultLocation': instance.defaultLocation,
      'ownerName': instance.ownerName,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
    };
