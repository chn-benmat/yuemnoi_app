import 'dart:convert';

import '../../../../core/models/rental_rates.dart';

enum RentalQueueStatus {
  invited,
  waiting,
  paused,
  ready,
  accepted,
  booked,
  left,
  expired,
}

class RentalQueueCardData {
  const RentalQueueCardData({
    required this.itemId,
    required this.name,
    required this.status,
    this.requestedByRenter = false,
    this.price,
    this.additionalDailyPrice,
    this.rentalType,
    this.rates,
    this.position,
    this.dueAt,
    this.expiresAt,
    this.acceptedAt,
    this.readyMessageId,
  });

  final int itemId;
  final String name;
  final RentalQueueStatus status;
  final bool requestedByRenter;
  final int? price;
  final int? additionalDailyPrice;
  final String? rentalType;

  /// เรตจากการ์ดรุ่นใหม่ (hourlyRate/dailyRate) การ์ดเก่าตีความจาก price/dailyPrice
  final RentalRates? rates;
  final int? position;
  final DateTime? dueAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;
  final String? readyMessageId;

  bool isRenterView({required bool isSender}) => isSender == requestedByRenter;

  String? get unitLabel => switch (rentalType) {
    'hourly' || 'hour' || 'รายชั่วโมง' => 'ชั่วโมง',
    'daily' || 'day' || 'รายวัน' => 'วัน',
    _ => null,
  };

  RentalRates get displayRates =>
      rates ??
      RentalRates.legacy(
        price: price,
        type: rentalType,
        dailyPrice: additionalDailyPrice,
      );

  static RentalQueueCardData? fromMessage(String text) {
    if (!text.startsWith('{"rentalQueue"')) return null;
    try {
      final data = jsonDecode(text)['rentalQueue'] as Map<String, dynamic>;
      final itemId = data['itemId'] as int;
      final name = data['name'] as String;
      if (itemId <= 0 || name.isEmpty) return null;
      return RentalQueueCardData(
        itemId: itemId,
        name: name,
        status: RentalQueueStatus.values.byName(data['status'] as String),
        requestedByRenter: data['requestedByRenter'] == true,
        price: data['price'] as int?,
        additionalDailyPrice: data['dailyPrice'] as int?,
        rentalType: data['rentalType'] as String?,
        rates: RentalRates.fromKeys(
          data,
          hourlyKey: 'hourlyRate',
          dailyKey: 'dailyRate',
        ),
        position: data['position'] as int?,
        dueAt: DateTime.tryParse(data['dueAt']?.toString() ?? ''),
        expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
        acceptedAt: DateTime.tryParse(data['acceptedAt']?.toString() ?? ''),
        readyMessageId: data['readyMessageId']?.toString(),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
