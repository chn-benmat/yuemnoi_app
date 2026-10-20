import 'package:equatable/equatable.dart';

import '../../domain/entities/item_detail.dart';
import '../../domain/entities/related_item.dart';

enum RelatedItemsStatus { initial, loading, loaded, failure }

enum ItemDetailStatus {
  initial,
  loading,
  loaded,
  updating,
  changingVisibility,
  deleting,
  deleted,
  failure,
}

class ItemDetailState extends Equatable {
  const ItemDetailState({
    this.status = ItemDetailStatus.initial,
    this.item,
    this.errorMessage,
    this.relatedItems = const [],
    this.relatedStatus = RelatedItemsStatus.initial,
  });

  final ItemDetailStatus status;
  final ItemDetail? item;
  final String? errorMessage;
  final List<RelatedItem> relatedItems;
  final RelatedItemsStatus relatedStatus;

  bool get isBusy =>
      status == ItemDetailStatus.loading ||
      status == ItemDetailStatus.updating ||
      status == ItemDetailStatus.changingVisibility ||
      status == ItemDetailStatus.deleting;

  ItemDetailState copyWith({
    ItemDetailStatus? status,
    ItemDetail? item,
    String? errorMessage,
    bool clearError = false,
    List<RelatedItem>? relatedItems,
    RelatedItemsStatus? relatedStatus,
  }) {
    return ItemDetailState(
      status: status ?? this.status,
      item: item ?? this.item,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      relatedItems: relatedItems ?? this.relatedItems,
      relatedStatus: relatedStatus ?? this.relatedStatus,
    );
  }

  @override
  List<Object?> get props => [
    status,
    item,
    errorMessage,
    relatedItems,
    relatedStatus,
  ];
}
