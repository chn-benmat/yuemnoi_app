import 'package:equatable/equatable.dart';

import '../../domain/entities/rental_item.dart';

enum RentalItemSubmissionStatus { initial, submitting, success, failure }

class RentalItemState extends Equatable {
  const RentalItemState({
    this.images = const [],
    this.status = RentalItemSubmissionStatus.initial,
    this.createdItem,
    this.errorMessage,
  });

  final List<RentalItemImage> images;
  final RentalItemSubmissionStatus status;
  final RentalItem? createdItem;
  final String? errorMessage;

  RentalItemState copyWith({
    List<RentalItemImage>? images,
    RentalItemSubmissionStatus? status,
    RentalItem? createdItem,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RentalItemState(
      images: images ?? this.images,
      status: status ?? this.status,
      createdItem: createdItem ?? this.createdItem,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [images, status, createdItem, errorMessage];
}
