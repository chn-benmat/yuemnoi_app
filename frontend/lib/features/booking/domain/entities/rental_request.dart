import 'package:equatable/equatable.dart';

class RentalRequestDraft extends Equatable {
  const RentalRequestDraft({
    required this.itemId,
    required this.startAt,
    required this.endAt,
    required this.rentalType,
    required this.pickupLocation,
  });

  final int itemId;
  final DateTime startAt;
  final DateTime endAt;
  final String rentalType;
  final String pickupLocation;

  @override
  List<Object?> get props => [
    itemId,
    startAt,
    endAt,
    rentalType,
    pickupLocation,
  ];
}

class RentalRequestResult extends Equatable {
  const RentalRequestResult({required this.id, required this.status});

  final int id;
  final String status;

  @override
  List<Object?> get props => [id, status];
}
