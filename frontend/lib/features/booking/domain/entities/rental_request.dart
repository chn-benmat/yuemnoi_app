import 'package:equatable/equatable.dart';

import '../../../../core/models/rental_penalty_terms.dart';

class RentalRequestDraft extends Equatable {
  const RentalRequestDraft({
    required this.itemId,
    required this.startAt,
    required this.endAt,
    required this.rentalType,
    required this.pickupLocation,
    this.offerMessageId,
    this.bookingId,
    this.conversationId,
    this.paymentMethod,
    this.unitPrice,
    this.queueMessageId,
    this.requestRevision,
    this.expectedPenaltyTerms,
  });

  final int itemId;
  final DateTime startAt;
  final DateTime endAt;
  final String rentalType;
  final String pickupLocation;
  final String? offerMessageId;
  final int? bookingId;
  final String? conversationId;
  final String? paymentMethod;
  final int? unitPrice;
  final int? queueMessageId;
  final int? requestRevision;
  final RentalPenaltyTerms? expectedPenaltyTerms;

  @override
  List<Object?> get props => [
    itemId,
    startAt,
    endAt,
    rentalType,
    pickupLocation,
    offerMessageId,
    bookingId,
    conversationId,
    paymentMethod,
    unitPrice,
    queueMessageId,
    requestRevision,
    expectedPenaltyTerms,
  ];
}

class RentalRequestResult extends Equatable {
  const RentalRequestResult({required this.id, required this.status});

  final int id;
  final String status;

  @override
  List<Object?> get props => [id, status];
}
