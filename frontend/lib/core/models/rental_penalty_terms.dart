import 'package:equatable/equatable.dart';

class RentalPenaltyTerms extends Equatable {
  const RentalPenaltyTerms({
    this.damageFee = 0,
    this.lateReturnFee = 0,
    this.damageTerms = '',
  });

  factory RentalPenaltyTerms.fromJson(Map<String, dynamic> json) =>
      RentalPenaltyTerms(
        damageFee: (json['damage_fee'] as num?)?.toInt() ?? 0,
        lateReturnFee: (json['late_return_fee'] as num?)?.toInt() ?? 0,
        damageTerms: json['damage_terms'] as String? ?? '',
      );

  final int damageFee;
  final int lateReturnFee;
  final String damageTerms;

  bool get isEmpty =>
      damageFee == 0 && lateReturnFee == 0 && damageTerms.isEmpty;

  Map<String, dynamic> toJson() => {
    'damage_fee': damageFee,
    'late_return_fee': lateReturnFee,
    'damage_terms': damageTerms,
  };

  @override
  List<Object?> get props => [damageFee, lateReturnFee, damageTerms];
}
