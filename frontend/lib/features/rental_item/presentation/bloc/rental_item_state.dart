import 'package:equatable/equatable.dart';

import '../../../identity/domain/rental_verification.dart';
import '../../domain/entities/rental_item.dart';

enum RentalItemSubmissionStatus { initial, submitting, success, failure }

class RentalItemState extends Equatable {
  const RentalItemState({
    this.images = const [],
    this.status = RentalItemSubmissionStatus.initial,
    this.createdItem,
    this.errorMessage,
    this.verification,
  });

  final List<RentalItemImage> images;
  final RentalItemSubmissionStatus status;
  final RentalItem? createdItem;
  final String? errorMessage;
  final RentalVerification? verification;

  RentalItemState copyWith({
    List<RentalItemImage>? images,
    RentalItemSubmissionStatus? status,
    RentalItem? createdItem,
    String? errorMessage,
    RentalVerification? verification,
    bool clearError = false,
  }) {
    return RentalItemState(
      images: images ?? this.images,
      status: status ?? this.status,
      createdItem: createdItem ?? this.createdItem,
      errorMessage: errorMessage ?? (clearError ? null : this.errorMessage),
      verification: verification ?? (clearError ? null : this.verification),
    );
  }

  @override
  List<Object?> get props => [
    images,
    status,
    createdItem,
    errorMessage,
    verification,
  ];
}
