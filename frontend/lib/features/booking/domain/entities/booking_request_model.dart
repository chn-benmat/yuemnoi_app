import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/models/pickup_location.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../../core/models/rental_penalty_terms.dart';

part 'booking_request_model.g.dart';

/// ประเภทการเช่า: รายชั่วโมง หรือ รายวัน
enum BookingRentalType {
  hourly('ต่อชั่วโมง', 'ชั่วโมง'),
  daily('ต่อวัน', 'วัน');

  const BookingRentalType(this.label, this.unit);
  final String label;
  final String unit;
}

/// ข้อมูลอุปกรณ์สำหรับการจอง
@JsonSerializable(explicitToJson: true)
class BookingItemInfo {
  @JsonKey(defaultValue: 1)
  final int id;
  @JsonKey(defaultValue: 'อุปกรณ์เช่า')
  final String title;
  @JsonKey(defaultValue: '')
  final String imageUrl;
  @JsonKey(defaultValue: 0.0)
  final double rating;
  @JsonKey(defaultValue: 0)
  final int reviewCount;
  @JsonKey(defaultValue: 100.0)
  final double hourlyRate;
  @JsonKey(defaultValue: 500.0)
  final double dailyRate;
  @JsonKey(defaultValue: 'นัดรับตามตกลง')
  final String defaultLocation;
  final String ownerName;
  final double? latitude;
  final double? longitude;
  @JsonKey(includeIfNull: false)
  final RentalPenaltyTerms? penaltyTerms;

  const BookingItemInfo({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.rating,
    required this.reviewCount,
    required this.hourlyRate,
    required this.dailyRate,
    required this.defaultLocation,
    this.ownerName = 'ผู้ปล่อยเช่า',
    this.latitude,
    this.longitude,
    this.penaltyTerms,
  });

  /// Mock เริ่มต้นตามดีไซน์ UI (Sony Alpha a7 IV)
  static const defaultMockItem = BookingItemInfo(
    id: 1,
    title: 'Sony Alpha a7 IV',
    imageUrl:
        'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?q=80&w=800&auto=format&fit=crop',
    rating: 0.0,
    reviewCount: 0,
    hourlyRate: 100.0,
    dailyRate: 500.0,
    defaultLocation: 'ซีคอน บางแค',
    ownerName: 'ผู้ปล่อยเช่า',
    latitude: 13.7115884,
    longitude: 100.4341077,
  );

  BookingItemInfo copyWith({
    int? id,
    String? title,
    String? imageUrl,
    double? rating,
    int? reviewCount,
    double? hourlyRate,
    double? dailyRate,
    String? defaultLocation,
    String? ownerName,
    double? latitude,
    double? longitude,
    RentalPenaltyTerms? penaltyTerms,
  }) {
    return BookingItemInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      dailyRate: dailyRate ?? this.dailyRate,
      defaultLocation: defaultLocation ?? this.defaultLocation,
      ownerName: ownerName ?? this.ownerName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      penaltyTerms: penaltyTerms ?? this.penaltyTerms,
    );
  }

  Map<String, dynamic> toJson() => _$BookingItemInfoToJson(this);

  factory BookingItemInfo.fromJson(Map<String, dynamic> json) =>
      _$BookingItemInfoFromJson(json);
}

/// ข้อมูลคำขอการจองเช่าอุปกรณ์ (รองรับทั้งรายชั่วโมงและรายวัน)
class BookingRequestData {
  final BookingItemInfo item;
  final BookingRentalType rentalType;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String location;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;

  LatLng? get pickupCoordinates =>
      mapPoint(latitude, longitude) ??
      matchingListingPoint(
        location,
        item.defaultLocation,
        mapPoint(item.latitude, item.longitude),
      );
  final String? conversationId;
  final String? ownerId;
  final String? originalMessageId;
  final String paymentMethod;
  final int? bookingId;
  final int? rentalQueueMessageId;
  final String? status;
  final bool isCustomerRequest;
  final int requestRevision;

  static const String bookingPayloadPrefix = '📋 คำขอเช่าอุปกรณ์';
  static const String metaStartTag = '[BOOKING_DATA:';
  static const String customerRequestMetaTag = '[RENTAL_REQUEST_DATA:';
  static const String metaEndTag = ']';
  static final _customerRequestMetadata = RegExp(
    r'\n\[RENTAL_REQUEST_DATA:([^\r\n]*)\]$',
  );

  const BookingRequestData({
    required this.item,
    this.rentalType = BookingRentalType.daily,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.conversationId,
    this.ownerId,
    this.originalMessageId,
    this.paymentMethod = 'cash',
    this.bookingId,
    this.rentalQueueMessageId,
    this.status,
    this.isCustomerRequest = false,
    this.requestRevision = 0,
  });

  /// ตรวจสอบว่าข้อความเป็นข้อความคำขอเช่าหรือไม่
  static bool isBookingRequest(String text) {
    return text.startsWith(bookingPayloadPrefix) || text.contains(metaStartTag);
  }

  /// ข้อมูลวิธีชำระเงิน
  bool get isPromptPay => paymentMethod == 'promptpay';
  String get paymentMethodLabel => isPromptPay ? 'PromptPay' : 'เงินสด';

  DateTime get _rentalEndDate =>
      rentalType == BookingRentalType.hourly ? startDate : endDate;

  /// แปลงข้อมูลคำขอเช่าเป็น Payload ข้อความสำหรับส่งในแชท
  String toChatMessagePayload() {
    final periodText = rentalType == BookingRentalType.daily
        ? '$formattedStartDate - $formattedEndDate ($duration วัน)'
        : '$formattedStartDate ($formattedStartTime - $formattedEndTime, $duration ชม.)';

    final jsonMap = {
      'itemId': item.id,
      'title': item.title,
      'imageUrl': item.imageUrl,
      'rating': item.rating,
      'reviewCount': item.reviewCount,
      'hourlyRate': item.hourlyRate,
      'dailyRate': item.dailyRate,
      'defaultLocation': item.defaultLocation,
      'ownerName': item.ownerName,
      'rentalType': rentalType.name,
      'startDate': startDate.toIso8601String(),
      'endDate': _rentalEndDate.toIso8601String(),
      'startHour': startTime.hour,
      'startMinute': startTime.minute,
      'endHour': endTime.hour,
      'endMinute': endTime.minute,
      'location': location,
      'locationAddress': locationAddress,
      'latitude': latitude,
      'longitude': longitude,
      'totalPrice': totalPrice,
      'paymentMethod': paymentMethod,
      'conversationId': conversationId,
      'ownerId': ownerId,
      if (originalMessageId != null) 'originalMessageId': originalMessageId,
      if (bookingId != null) 'bookingId': bookingId,
      if (rentalQueueMessageId != null)
        'rentalQueueMessageId': rentalQueueMessageId,
      if (status != null) 'status': status,
      if (requestRevision > 0) 'requestRevision': requestRevision,
    };

    final jsonString = jsonEncode(jsonMap);
    final tag = isCustomerRequest ? customerRequestMetaTag : metaStartTag;

    return '''$bookingPayloadPrefix
อุปกรณ์: ${item.title}
ช่วงเวลา: $periodText
สถานที่นัดพบ: $location
วิธีชำระเงิน: $paymentMethodLabel
ยอดรวม: ${totalPrice.toStringAsFixed(0)} ฿
$tag$jsonString$metaEndTag''';
  }

  /// แปลงข้อความแชทกลับมาเป็น BookingRequestData
  static BookingRequestData? fromChatMessage(
    String text, {
    String? imageUrl,
    String? messageId,
  }) {
    final customerMetadata = text.startsWith(bookingPayloadPrefix)
        ? _customerRequestMetadata.firstMatch(text)?.group(1)
        : null;
    try {
      final isCustomerRequest = customerMetadata != null;
      final legacyStart = text.indexOf(metaStartTag);
      final endIdx = text.lastIndexOf(metaEndTag);
      final startIdx = legacyStart + metaStartTag.length;
      final jsonStr =
          customerMetadata ??
          (legacyStart >= 0 && startIdx < endIdx
              ? text.substring(startIdx, endIdx)
              : null);
      if (jsonStr != null) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (isCustomerRequest &&
            ((map['bookingId'] as num?)?.toInt() ?? 0) <= 0) {
          return null;
        }

        final item = BookingItemInfo.fromJson({
          ...map,
          'id': map['itemId'],
          'imageUrl': (imageUrl != null && imageUrl.isNotEmpty)
              ? imageUrl
              : map['imageUrl'],
        });

        final rentalType = map['rentalType'] == 'hourly'
            ? BookingRentalType.hourly
            : BookingRentalType.daily;

        final startDate = map['startDate'] != null
            ? DateTime.tryParse(map['startDate'] as String) ?? DateTime.now()
            : DateTime.now();

        final endDate = map['endDate'] != null
            ? DateTime.tryParse(map['endDate'] as String) ??
                  startDate.add(const Duration(days: 1))
            : startDate.add(const Duration(days: 1));

        final startTime = TimeOfDay(
          hour: (map['startHour'] as num?)?.toInt() ?? 9,
          minute: (map['startMinute'] as num?)?.toInt() ?? 0,
        );

        final endTime = TimeOfDay(
          hour: (map['endHour'] as num?)?.toInt() ?? 17,
          minute: (map['endMinute'] as num?)?.toInt() ?? 0,
        );

        final resolvedOriginalMessageId =
            messageId ?? (map['originalMessageId'] as String?);

        return BookingRequestData(
          item: item,
          bookingId: (map['bookingId'] as num?)?.toInt(),
          rentalQueueMessageId: (map['rentalQueueMessageId'] as num?)?.toInt(),
          status: map['status'] as String?,
          isCustomerRequest: isCustomerRequest,
          requestRevision: (map['requestRevision'] as num?)?.toInt() ?? 0,
          rentalType: rentalType,
          startDate: startDate,
          endDate: endDate,
          startTime: startTime,
          endTime: endTime,
          location: map['location'] as String? ?? 'นัดรับตามตกลง',
          locationAddress: map['locationAddress'] as String?,
          latitude: (map['latitude'] as num?)?.toDouble(),
          longitude: (map['longitude'] as num?)?.toDouble(),
          conversationId: map['conversationId'] as String?,
          ownerId: map['ownerId'] as String?,
          originalMessageId: resolvedOriginalMessageId,
          paymentMethod: map['paymentMethod'] as String? ?? 'cash',
        );
      }
    } catch (_) {}

    if (customerMetadata == null && isBookingRequest(text)) {
      // Fallback สำหรับกรณีข้อความพื้นฐาน
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return BookingRequestData(
        item: const BookingItemInfo(
          id: 1,
          title: 'อุปกรณ์เช่า',
          imageUrl: '',
          rating: 0.0,
          reviewCount: 0,
          hourlyRate: 100.0,
          dailyRate: 500.0,
          defaultLocation: 'นัดรับตามตกลง',
          latitude: 13.7115884,
          longitude: 100.4341077,
        ),
        startDate: today,
        endDate: today.add(const Duration(days: 1)),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        location: 'นัดรับตามตกลง',
        originalMessageId: messageId,
      );
    }

    return null;
  }

  /// เวลาเริ่มต้นและสิ้นสุดแบบ DateTime เต็มรูปแบบ
  DateTime get startDateTime => DateTime(
    startDate.year,
    startDate.month,
    startDate.day,
    startTime.hour,
    startTime.minute,
  );

  bool get hasQueueOfferStartPassed =>
      rentalQueueMessageId != null && _hasStartPassed(startDateTime);

  static const _bangkokOffset = Duration(hours: 7);

  static DateTime get todayInBangkok =>
      DateUtils.dateOnly(DateTime.now().toUtc().add(_bangkokOffset));

  DateTime get requestStartAt => _bangkokToUtc(startDate, startTime);

  DateTime get requestEndAt => _bangkokToUtc(
    _rentalEndDate,
    rentalType == BookingRentalType.hourly ? endTime : startTime,
  );

  bool get hasCustomerRequestStartPassed =>
      isCustomerRequest && _hasStartPassed(requestStartAt);

  bool _hasStartPassed(DateTime startAt) {
    if (rentalType == BookingRentalType.daily) {
      return DateUtils.dateOnly(startDate).isBefore(todayInBangkok);
    }
    return !startAt.isAfter(DateTime.now());
  }

  DateTime _bangkokToUtc(DateTime day, TimeOfDay time) => DateTime.utc(
    day.year,
    day.month,
    day.day,
    time.hour,
    time.minute,
  ).subtract(_bangkokOffset);

  DateTime get endDateTime {
    final date = _rentalEndDate;
    final time = rentalType == BookingRentalType.hourly ? endTime : startTime;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  /// ราคาต่อหน่วยตามประเภทการเช่า
  double get unitRate =>
      rentalType == BookingRentalType.hourly ? item.hourlyRate : item.dailyRate;

  /// จำนวนระยะเวลา (ชั่วโมง หรือ วัน)
  int get duration {
    if (rentalType == BookingRentalType.daily) {
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      final days = end.difference(start).inDays;
      return days < 1 ? 1 : days;
    } else {
      final startMinutes = startTime.hour * 60 + startTime.minute;
      final endMinutes = endTime.hour * 60 + endTime.minute;
      int diffMinutes = endMinutes - startMinutes;
      if (diffMinutes <= 0) {
        diffMinutes = 120; // ค่าเริ่มต้นอย่างน้อย 2 ชม.
      }
      final hours = (diffMinutes / 60).ceil();
      return hours < 1 ? 1 : hours;
    }
  }

  /// คำนวณราคารวม
  double get totalPrice => unitRate * duration;

  /// ข้อความแจกแจงราคา เช่น "ค่าเช่า (500฿ x 2 วัน)" หรือ "ค่าเช่า (100฿ x 4 ชั่วโมง)"
  String get priceBreakdownLabel {
    final rateStr = unitRate.toStringAsFixed(0);
    final count = duration;
    final unitStr = rentalType.unit;
    return 'ค่าเช่า ($rateStr฿ x $count $unitStr)';
  }

  /// วันที่เริ่มต้นฟอร์แมต dd/MM/yyyy
  String get formattedStartDate => DateFormat('dd/MM/yyyy').format(startDate);

  /// วันที่สิ้นสุดฟอร์แมต dd/MM/yyyy
  String get formattedEndDate => DateFormat('dd/MM/yyyy').format(endDate);

  /// วันที่และช่วงเวลาแบบสรุปสวยงาม
  String get formattedPeriodSummary {
    if (rentalType == BookingRentalType.daily) {
      return '$formattedStartDate - $formattedEndDate ($duration วัน)';
    } else {
      return '$formattedStartDate ($formattedStartTime - $formattedEndTime, $duration ชม.)';
    }
  }

  /// วันที่และช่วงเวลาแบบละเอียด (ระบุ วัน เดือน ปี และเวลาที่จะเช่า)
  String get formattedDetailedRentalPeriod {
    if (rentalType == BookingRentalType.daily) {
      return '$formattedStartDate - $formattedEndDate ($duration วัน)';
    } else {
      return '$formattedStartDate เวลา $formattedStartTime - $formattedEndTime ($duration ชม.)';
    }
  }

  /// เวลาเริ่มต้นฟอร์แมต HH:mm น.
  String formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute น.';
  }

  String get formattedStartTime => formatTime(startTime);
  String get formattedEndTime => formatTime(endTime);

  BookingRequestData copyWith({
    BookingItemInfo? item,
    BookingRentalType? rentalType,
    DateTime? startDate,
    DateTime? endDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? location,
    String? locationAddress,
    double? latitude,
    double? longitude,
    String? conversationId,
    String? ownerId,
    String? originalMessageId,
    String? paymentMethod,
    int? bookingId,
    int? rentalQueueMessageId,
    String? status,
  }) {
    return BookingRequestData(
      item: item ?? this.item,
      rentalType: rentalType ?? this.rentalType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      locationAddress: locationAddress ?? this.locationAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      conversationId: conversationId ?? this.conversationId,
      ownerId: ownerId ?? this.ownerId,
      originalMessageId: originalMessageId ?? this.originalMessageId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      bookingId: bookingId ?? this.bookingId,
      rentalQueueMessageId: rentalQueueMessageId ?? this.rentalQueueMessageId,
      status: status ?? this.status,
      isCustomerRequest: isCustomerRequest,
      requestRevision: requestRevision,
    );
  }
}
