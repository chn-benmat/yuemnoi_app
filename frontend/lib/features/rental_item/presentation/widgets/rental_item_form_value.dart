import '../../../../core/models/pickup_location.dart';
import '../../../../core/models/rental_penalty_terms.dart';
import '../../domain/entities/rental_item.dart';

class RentalItemFormValue {
  const RentalItemFormValue({
    this.name = '',
    this.category,
    this.description = '',
    this.hourlyPrice = '',
    this.dailyPrice = '',
    this.damageFee = '',
    this.lateReturnFee = '',
    this.damageTerms = '',
    this.photos = const [],
    this.pickupLocation,
  });

  final String name;
  final String? category;
  final String description;
  final String hourlyPrice;
  final String dailyPrice;
  final String damageFee;
  final String lateReturnFee;
  final String damageTerms;
  final List<RentalItemPhoto> photos;
  final PickupLocation? pickupLocation;

  String get rentalType =>
      int.tryParse(hourlyPrice) != null ? 'รายชั่วโมง' : 'รายวัน';
  int? get price => int.tryParse(hourlyPrice) ?? int.tryParse(dailyPrice);
  int? get additionalDailyPrice =>
      rentalType == 'รายชั่วโมง' ? int.tryParse(dailyPrice) : null;
  RentalPenaltyTerms get penaltyTerms => RentalPenaltyTerms(
    damageFee: int.tryParse(damageFee) ?? 0,
    lateReturnFee: int.tryParse(lateReturnFee) ?? 0,
    damageTerms: damageTerms,
  );
}
