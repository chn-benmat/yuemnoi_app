import '../../domain/entities/item_detail.dart';
import '../../domain/repositories/item_detail_repository.dart';
import '../datasources/item_detail_remote_data_source.dart';

class ItemDetailRepositoryImpl implements ItemDetailRepository {
  const ItemDetailRepositoryImpl(this.remoteDataSource);

  final ItemDetailRemoteDataSource remoteDataSource;

  @override
  Future<ItemDetail> fetchById(int itemId) async {
    try {
      return await remoteDataSource.fetchById(itemId);
    } on ItemDetailRemoteException catch (error) {
      throw ItemDetailException(error.message);
    }
  }

  @override
  Future<ItemDetail> update(ItemEditDraft draft) async {
    try {
      return await remoteDataSource.update(draft);
    } on ItemDetailRemoteException catch (error) {
      throw ItemDetailException(error.message);
    }
  }
}
