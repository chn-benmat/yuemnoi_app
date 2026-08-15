import '../entities/item_detail.dart';
import '../repositories/item_detail_repository.dart';

class UpdateItemUseCase {
  const UpdateItemUseCase(this.repository);

  final ItemDetailRepository repository;

  Future<ItemDetail> execute(ItemEditDraft draft) => repository.update(draft);
}
