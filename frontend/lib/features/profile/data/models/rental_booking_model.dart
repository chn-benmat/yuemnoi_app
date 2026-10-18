import 'dart:convert';

import '../../domain/entities/rental_booking.dart';

// คำอธิบาย: Model สำหรับแปลงข้อมูลการจอง/เช่า/ปล่อยเช่าจาก booking_tb ในชั้น Data
class RentalBookingModel {
  final int? bookingId;
  final int? itemId;
  final String title;
  final String partnerName;
  final String? partnerPhone;
  final String partnerRole;
  final String status;
  final String statusCode;
  final String? category;
  final String? imageUrl;
  final DateTime? startDate;
  final DateTime? endDate;
  final String duration;
  final double totalPrice;
  final String? pickupLocation;
  final bool isOwner;

  const RentalBookingModel({
    this.bookingId,
    this.itemId,
    required this.title,
    required this.partnerName,
    this.partnerPhone,
    required this.partnerRole,
    required this.status,
    required this.statusCode,
    this.category,
    this.imageUrl,
    this.startDate,
    this.endDate,
    this.duration = '',
    this.totalPrice = 0.0,
    this.pickupLocation,
    this.isOwner = false,
  });

  factory RentalBookingModel.fromSupabase({
    required Map<String, dynamic> booking,
    Map<String, dynamic>? itemData,
    String? partnerName,
    String? partnerPhone,
    required bool isOwner,
  }) {
    final itemId = (booking['item_id'] as num?)?.toInt();
    final title = itemData?['item_name']?.toString() ?? 'อุปกรณ์เช่า';
    final category = itemData?['category']?.toString();
    final imageUrl = _extractImageUrl(itemData?['item_image_url']);

    final (startDate, endDate) = _parseDates(booking);
    final duration = _calculateDuration(booking, startDate, endDate);
    final statusCode = booking['status']?.toString() ?? 'confirmed';
    final statusText = _formatStatusText(
      statusCode,
      isRenter: !isOwner,
      startDate: startDate,
    );

    final rawPrice = booking['total_price'] ?? booking['price'];
    final price = (rawPrice as num?)?.toDouble() ?? 0.0;

    return RentalBookingModel(
      bookingId: (booking['id'] as num?)?.toInt(),
      itemId: itemId,
      title: title,
      partnerName: partnerName ?? (isOwner ? 'ผู้เช่า' : 'เจ้าของอุปกรณ์'),
      partnerPhone: partnerPhone,
      partnerRole: isOwner ? 'ผู้เช่า' : 'เจ้าของอุปกรณ์',
      status: statusText,
      statusCode: statusCode,
      category: category,
      imageUrl: imageUrl,
      startDate: startDate,
      endDate: endDate,
      duration: duration,
      totalPrice: price,
      pickupLocation: booking['pickup_location']?.toString(),
      isOwner: isOwner,
    );
  }

  RentalBooking toEntity() {
    return RentalBooking(
      bookingId: bookingId,
      itemId: itemId,
      title: title,
      partnerName: partnerName,
      partnerPhone: partnerPhone,
      partnerRole: partnerRole,
      status: status,
      statusCode: statusCode,
      category: category,
      imageUrl: imageUrl,
      startDate: startDate,
      endDate: endDate,
      duration: duration,
      totalPrice: totalPrice,
      pickupLocation: pickupLocation,
      isOwner: isOwner,
    );
  }

  static (DateTime?, DateTime?) _parseDates(Map<String, dynamic> b) {
    DateTime? start;
    DateTime? end;

    if (b['start_at'] != null) {
      start = DateTime.tryParse(b['start_at'].toString());
    } else if (b['start_date'] != null) {
      start = DateTime.tryParse(b['start_date'].toString());
    }

    if (b['end_at'] != null) {
      end = DateTime.tryParse(b['end_at'].toString());
    } else if (b['end_date'] != null) {
      end = DateTime.tryParse(b['end_date'].toString());
    }

    return (start, end);
  }

  static String _calculateDuration(
    Map<String, dynamic> b,
    DateTime? start,
    DateTime? end,
  ) {
    if (start != null && end != null) {
      final diff = end.difference(start);
      if (b['type'] == 'รายชั่วโมง' || diff.inDays == 0) {
        final hours = diff.inHours > 0 ? diff.inHours : 1;
        return 'เช่า $hours ชั่วโมง';
      } else {
        final days = diff.inDays > 0 ? diff.inDays : 1;
        return 'เช่า $days วัน';
      }
    }
    return 'เช่า 1 วัน';
  }

  static String _formatStatusText(
    String? rawStatus, {
    required bool isRenter,
    DateTime? startDate,
  }) {
    final status = rawStatus?.toLowerCase().trim();
    switch (status) {
      case 'pending':
        return isRenter ? 'รอการยืนยัน' : 'มีคำขอเช่าใหม่';
      case 'confirmed':
        if (startDate != null) {
          final now = DateTime.now();
          final startDay = DateTime(startDate.year, startDate.month, startDate.day);
          final today = DateTime(now.year, now.month, now.day);
          if (today.isBefore(startDay)) {
            final days = startDay.difference(today).inDays;
            return 'รอนัดรับ (อีก $days วัน)';
          }
        }
        return 'ยืนยันแล้ว / นัดรับของ';
      case 'active':
        return 'กำลังเช่า';
      case 'completed':
      case 'finished':
        return 'เสร็จสิ้น';
      case 'cancelled':
        return 'ยกเลิกแล้ว';
      default:
        return status ?? 'ยืนยันแล้ว';
    }
  }

  static String? _extractImageUrl(dynamic raw) {
    if (raw == null) return null;
    if (raw is List && raw.isNotEmpty) {
      return raw.first.toString();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List && decoded.isNotEmpty) {
            return decoded.first.toString();
          }
        } catch (_) {}
      }
      if (trimmed.startsWith('http')) return trimmed;
    }
    return null;
  }
}
