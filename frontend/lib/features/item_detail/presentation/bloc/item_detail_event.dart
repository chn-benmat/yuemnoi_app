import 'package:equatable/equatable.dart';

import '../../domain/entities/item_detail.dart';

sealed class ItemDetailEvent extends Equatable {
  const ItemDetailEvent();

  @override
  List<Object?> get props => const [];
}

class ItemDetailRequested extends ItemDetailEvent {
  const ItemDetailRequested(this.itemId);

  final int itemId;

  @override
  List<Object?> get props => [itemId];
}

class ItemDetailUpdateSubmitted extends ItemDetailEvent {
  const ItemDetailUpdateSubmitted(this.draft);

  final ItemEditDraft draft;

  @override
  List<Object?> get props => [draft];
}
