import 'package:equatable/equatable.dart';

enum RentalRequestStatus {
  initial,
  submitting,
  success,
  confirming,
  confirmed,
  failure,
}

class RentalRequestState extends Equatable {
  const RentalRequestState({
    this.status = RentalRequestStatus.initial,
    this.rentalId,
    this.rentalStatus,
    this.errorMessage,
  });

  final RentalRequestStatus status;
  final int? rentalId;
  final String? rentalStatus;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, rentalId, rentalStatus, errorMessage];
}
