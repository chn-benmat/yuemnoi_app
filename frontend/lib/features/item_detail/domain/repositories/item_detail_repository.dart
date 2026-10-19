import '../entities/item_detail.dart';

class ItemDetailException implements Exception {
  const ItemDetailException(this.message);

  final String message;
}

abstract interface class ItemDetailRepository {
  Future<ItemDetail> fetchById(int itemId);

  Future<ItemDetail> update(ItemEditDraft draft);

  Future<ItemDetail> setVisibility(int itemId, {required bool hidden});

  Future<void> delete(int itemId);
}
