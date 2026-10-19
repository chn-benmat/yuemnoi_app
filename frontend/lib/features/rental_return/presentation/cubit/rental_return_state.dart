import 'package:equatable/equatable.dart';

import '../../domain/entities/rental_return_session.dart';

enum RentalReturnStatus { initial, loading, loaded, error }

class RentalReturnState extends Equatable {
  final RentalReturnStatus status;
  final RentalReturnSession session;
  final RentalUserRole activeRole;
  final bool isAlarmActive;
  final bool isSubmitting;
  final String? errorMessage;
  final String? successMessage;
  final DateTime? merchantQrExpiry;

  const RentalReturnState({
    this.status = RentalReturnStatus.initial,
    required this.session,
    this.activeRole = RentalUserRole.renter,
    this.isAlarmActive = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.successMessage,
    this.merchantQrExpiry,
  });

  bool get isRenter => activeRole == RentalUserRole.renter;
  bool get isLender => activeRole == RentalUserRole.lender;

  RentalReturnState copyWith({
    RentalReturnStatus? status,
    RentalReturnSession? session,
    RentalUserRole? activeRole,
    bool? isAlarmActive,
    bool? isSubmitting,
    String? errorMessage,
    String? successMessage,
    DateTime? merchantQrExpiry,
  }) {
    return RentalReturnState(
      status: status ?? this.status,
      session: session ?? this.session,
      activeRole: activeRole ?? this.activeRole,
      isAlarmActive: isAlarmActive ?? this.isAlarmActive,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      successMessage: successMessage,
      merchantQrExpiry: merchantQrExpiry ?? this.merchantQrExpiry,
    );
  }

  @override
  List<Object?> get props => [
    status,
    session,
    activeRole,
    isAlarmActive,
    isSubmitting,
    errorMessage,
    successMessage,
    merchantQrExpiry,
  ];
}
