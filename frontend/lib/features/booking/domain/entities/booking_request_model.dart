import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// ประเภทการเช่า: รายชั่วโมง หรือ รายวัน
enum BookingRentalType {
  hourly('ต่อชั่วโมง', 'ชั่วโมง'),
  daily('ต่อวัน', 'วัน');

  const BookingRentalType(this.label, this.unit);
  final String label;
  final String unit;
}

/// วิธีการชำระเงิน
enum BookingPaymentMethod {
  bankTransfer('ธนาคาร', 'โอนผ่านบัญชีธนาคาร'),
  wallet('เงินในบัญชี', 'กระเป๋าเงิน Yuemnoi Pay'),
  promptPay('PromptPay', 'พร้อมเพย์ QR Code');

  const BookingPaymentMethod(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// ข้อมูลอุปกรณ์สำหรับการจอง
class BookingItemInfo {
  final int id;
  final String title;
  final String imageUrl;
  final double rating;
  final int reviewCount;
  final double hourlyRate;
  final double dailyRate;
  final String defaultLocation;
  final String ownerName;

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
  });

  /// Mock เริ่มต้นตามดีไซน์ UI (Sony Alpha a7 IV)
  static const defaultMockItem = BookingItemInfo(
    id: 1,
    title: 'Sony Alpha a7 IV',
    imageUrl:
        'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?q=80&w=800&auto=format&fit=crop',
    rating: 4.9,
    reviewCount: 124,
    hourlyRate: 100.0,
    dailyRate: 500.0,
    defaultLocation: 'ซีคอน บางแค',
    ownerName: 'ผู้ปล่อยเช่า',
  );
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
  final BookingPaymentMethod paymentMethod;

  const BookingRequestData({
    required this.item,
    this.rentalType = BookingRentalType.daily,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.locationNote = 'เลือกโดยผู้ปล่อยเช่า',
    this.paymentMethod = BookingPaymentMethod.bankTransfer,
  });

  /// ราคาต่อหน่วยตามประเภทการเช่า
  double get unitRate =>
      rentalType == BookingRentalType.hourly ? item.hourlyRate : item.dailyRate;

  /// จำนวนระยะเวลา (ชั่วโมง หรือ วัน)
  int get duration {
    if (rentalType == BookingRentalType.daily) {
      final days = endDate.difference(startDate).inDays + 1;
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
  String get formattedStartDate =>
      DateFormat('dd/MM/yyyy').format(startDate);

  /// วันที่สิ้นสุดฟอร์แมต dd/MM/yyyy
  String get formattedEndDate =>
      DateFormat('dd/MM/yyyy').format(endDate);

  /// เวลาเริ่มต้นฟอร์แมต HH : mm
  String formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour : $minute';
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
    BookingPaymentMethod? paymentMethod,
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
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}
