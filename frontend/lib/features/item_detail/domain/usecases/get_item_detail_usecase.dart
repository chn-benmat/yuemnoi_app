import '../entities/item_detail.dart';
import '../repositories/item_detail_repository.dart';

class GetItemDetailUseCase {
  const GetItemDetailUseCase(this.repository);

  final ItemDetailRepository repository;

  Future<ItemDetail> execute(int itemId) => repository.fetchById(itemId);
}
