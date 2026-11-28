import 'package:equatable/equatable.dart';

class RelatedItem extends Equatable {
  const RelatedItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.rentalType,
    this.imageUrl = '',
    this.locationName = 'ไม่ระบุตำแหน่ง',
    this.paidBookingCount = 0,
    this.isRentalOccupied = false,
  });

  final int id;
  final String name;
  final String category;
  final int price;
  final String rentalType;
  final String imageUrl;
  final String locationName;
  final int paidBookingCount;
  final bool isRentalOccupied;

  String get unitLabel =>
      rentalType == 'hourly' || rentalType == 'รายชั่วโมง' ? 'ชั่วโมง' : 'วัน';

  @override
  List<Object?> get props => [
    id,
    name,
    category,
    price,
    rentalType,
    imageUrl,
    locationName,
    paidBookingCount,
    isRentalOccupied,
  ];
}
