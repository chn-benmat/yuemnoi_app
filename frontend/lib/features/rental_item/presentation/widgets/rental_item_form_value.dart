import '../../../../core/models/pickup_location.dart';
import '../../domain/entities/rental_item.dart';

class RentalItemFormValue {
  const RentalItemFormValue({
    this.name = '',
    this.category,
    this.description = '',
    this.rentalType,
    this.price = '',
    this.photos = const [],
    this.pickupLocation,
  });

  final String name;
  final String? category;
  final String description;
  final String? rentalType;
  final String price;
  final List<RentalItemPhoto> photos;
  final PickupLocation? pickupLocation;

  String get unit => rentalType == 'รายชั่วโมง' ? 'ชั่วโมง' : 'วัน';
}
