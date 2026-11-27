import 'package:equatable/equatable.dart';

import '../../../identity/domain/rental_verification.dart';

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
    this.verification,
  });

  final RentalRequestStatus status;
  final int? rentalId;
  final String? rentalStatus;
  final String? errorMessage;
  final RentalVerification? verification;

  @override
  List<Object?> get props => [
    status,
    rentalId,
    rentalStatus,
    errorMessage,
    verification,
  ];
}
