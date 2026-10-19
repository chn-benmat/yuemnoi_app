import 'package:equatable/equatable.dart';

import '../../domain/entities/item_detail.dart';

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
  });

  final ItemDetailStatus status;
  final ItemDetail? item;
  final String? errorMessage;

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
  }) {
    return ItemDetailState(
      status: status ?? this.status,
      item: item ?? this.item,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, item, errorMessage];
}
