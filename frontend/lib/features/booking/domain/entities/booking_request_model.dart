import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

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
@JsonSerializable()
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
  final String locationNote;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final String? conversationId;
  final String? ownerId;
  final String? originalMessageId;
  final String paymentMethod;
  final int? bookingId;
  final String? status;

  static const String bookingPayloadPrefix = '📋 คำขอเช่าอุปกรณ์';
  static const String metaStartTag = '[BOOKING_DATA:';
  static const String metaEndTag = ']';

  const BookingRequestData({
    required this.item,
    this.rentalType = BookingRentalType.daily,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.locationNote = 'เลือกโดยผู้ปล่อยเช่า',
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.conversationId,
    this.ownerId,
    this.originalMessageId,
    this.paymentMethod = 'cash',
    this.bookingId,
    this.status,
  });

  /// ตรวจสอบว่าข้อความเป็นข้อความคำขอเช่าหรือไม่
  static bool isBookingRequest(String text) {
    return text.startsWith(bookingPayloadPrefix) || text.contains(metaStartTag);
  }

  /// ข้อมูลวิธีชำระเงิน
  bool get isPromptPay => paymentMethod == 'promptpay';
  String get paymentMethodLabel => isPromptPay ? 'PromptPay' : 'เงินสด';

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
      'endDate': endDate.toIso8601String(),
      'startHour': startTime.hour,
      'startMinute': startTime.minute,
      'endHour': endTime.hour,
      'endMinute': endTime.minute,
      'location': location,
      'locationNote': locationNote,
      'locationAddress': locationAddress,
      'totalPrice': totalPrice,
      'paymentMethod': paymentMethod,
      'conversationId': conversationId,
      'ownerId': ownerId,
      if (originalMessageId != null) 'originalMessageId': originalMessageId,
      if (bookingId != null) 'bookingId': bookingId,
      if (status != null) 'status': status,
    };

    final jsonString = jsonEncode(jsonMap);

    return '''$bookingPayloadPrefix
อุปกรณ์: ${item.title}
ช่วงเวลา: $periodText
สถานที่นัดพบ: $location
วิธีชำระเงิน: $paymentMethodLabel
ยอดรวม: ${totalPrice.toStringAsFixed(0)} ฿
$metaStartTag$jsonString$metaEndTag''';
  }

  /// แปลงข้อความแชทกลับมาเป็น BookingRequestData
  static BookingRequestData? fromChatMessage(
    String text, {
    String? imageUrl,
    String? messageId,
  }) {
    try {
      if (text.contains(metaStartTag) && text.contains(metaEndTag)) {
        final startIdx = text.indexOf(metaStartTag) + metaStartTag.length;
        final endIdx = text.lastIndexOf(metaEndTag);
        if (startIdx < endIdx) {
          final jsonStr = text.substring(startIdx, endIdx);
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;

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
              (map['originalMessageId'] as String?) ?? messageId;

          return BookingRequestData(
            item: item,
            bookingId: (map['bookingId'] as num?)?.toInt(),
            status: map['status'] as String?,
            rentalType: rentalType,
            startDate: startDate,
            endDate: endDate,
            startTime: startTime,
            endTime: endTime,
            location: map['location'] as String? ?? 'นัดรับตามตกลง',
            locationNote:
                map['locationNote'] as String? ?? 'เลือกโดยผู้ปล่อยเช่า',
            locationAddress: map['locationAddress'] as String?,
            // พิกัดเป็นข้อมูลของประกาศอุปกรณ์ ไม่อ่านจากข้อมูลคำขอเช่าเก่า
            latitude: null,
            longitude: null,
            conversationId: map['conversationId'] as String?,
            ownerId: map['ownerId'] as String?,
            originalMessageId: resolvedOriginalMessageId,
            paymentMethod: map['paymentMethod'] as String? ?? 'cash',
          );
        }
      }
    } catch (_) {}

    if (isBookingRequest(text)) {
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

  DateTime get endDateTime => rentalType == BookingRentalType.daily
      ? DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          startTime.hour,
          startTime.minute,
        )
      : DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
          endTime.hour,
          endTime.minute,
        );

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
    String? locationNote,
    String? locationAddress,
    double? latitude,
    double? longitude,
    String? conversationId,
    String? ownerId,
    String? originalMessageId,
    String? paymentMethod,
    int? bookingId,
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
      locationNote: locationNote ?? this.locationNote,
      locationAddress: locationAddress ?? this.locationAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      conversationId: conversationId ?? this.conversationId,
      ownerId: ownerId ?? this.ownerId,
      originalMessageId: originalMessageId ?? this.originalMessageId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      bookingId: bookingId ?? this.bookingId,
      status: status ?? this.status,
    );
  }
}
