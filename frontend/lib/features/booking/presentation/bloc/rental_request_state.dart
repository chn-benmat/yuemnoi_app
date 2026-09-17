import 'package:equatable/equatable.dart';

enum RentalRequestStatus { initial, submitting, success, failure }

class RentalRequestState extends Equatable {
  const RentalRequestState({
    this.status = RentalRequestStatus.initial,
    this.rentalId,
    this.errorMessage,
  });

  final RentalRequestStatus status;
  final int? rentalId;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, rentalId, errorMessage];
}
