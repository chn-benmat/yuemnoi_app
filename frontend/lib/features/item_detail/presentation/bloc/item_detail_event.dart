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

class ItemRelatedItemsRequested extends ItemDetailEvent {
  const ItemRelatedItemsRequested(this.item);
  final ItemDetail item;

  @override
  List<Object?> get props => [item];
}

class ItemVisibilityChanged extends ItemDetailEvent {
  const ItemVisibilityChanged({required this.hidden});
  final bool hidden;
  @override
  List<Object?> get props => [hidden];
}

class ItemDeleteSubmitted extends ItemDetailEvent {
  const ItemDeleteSubmitted();
}

class ItemDetailUpdateSubmitted extends ItemDetailEvent {
  const ItemDetailUpdateSubmitted(this.draft);

  final ItemEditDraft draft;

  @override
  List<Object?> get props => [draft];
}
