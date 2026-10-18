import '../entities/item_detail.dart';
import '../repositories/item_detail_repository.dart';

class ManageOwnerItemUseCase {
  const ManageOwnerItemUseCase(this.repository);
  final ItemDetailRepository repository;

  Future<ItemDetail> setVisibility(ItemDetail item, {required bool hidden}) {
    _requireOwner(item);
    return repository.setVisibility(item.id, hidden: hidden);
  }

  Future<void> delete(ItemDetail item) {
    _requireOwner(item);
    return repository.delete(item.id);
  }

  void _requireOwner(ItemDetail item) {
    if (!item.isOwner) {
      throw const ItemDetailException(
        'เฉพาะเจ้าของเท่านั้นที่จัดการอุปกรณ์ได้',
      );
    }
  }
}
