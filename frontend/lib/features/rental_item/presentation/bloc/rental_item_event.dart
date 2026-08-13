import 'package:equatable/equatable.dart';

import '../../domain/entities/rental_item.dart';

sealed class RentalItemEvent extends Equatable {
  const RentalItemEvent();
}

class RentalItemImagesAdded extends RentalItemEvent {
  const RentalItemImagesAdded(this.images);
  final List<RentalItemImage> images;

  @override
  List<Object?> get props => [images];
}

class RentalItemImageRemoved extends RentalItemEvent {
  const RentalItemImageRemoved(this.index);
  final int index;

  @override
  List<Object?> get props => [index];
}

class RentalItemSubmitted extends RentalItemEvent {
  const RentalItemSubmitted(this.draft);
  final RentalItemDraft draft;

  @override
  List<Object?> get props => [draft];
}
