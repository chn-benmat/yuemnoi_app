import 'dart:convert';

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
    this.price,
    this.rentalType,
    this.position,
    this.dueAt,
    this.expiresAt,
    this.acceptedAt,
  });

  final int itemId;
  final String name;
  final RentalQueueStatus status;
  final int? price;
  final String? rentalType;
  final int? position;
  final DateTime? dueAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;

  String? get unitLabel => switch (rentalType) {
    'hourly' || 'hour' || 'รายชั่วโมง' => 'ชั่วโมง',
    'daily' || 'day' || 'รายวัน' => 'วัน',
    _ => null,
  };

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
        price: data['price'] as int?,
        rentalType: data['rentalType'] as String?,
        position: data['position'] as int?,
        dueAt: DateTime.tryParse(data['dueAt']?.toString() ?? ''),
        expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
        acceptedAt: DateTime.tryParse(data['acceptedAt']?.toString() ?? ''),
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
