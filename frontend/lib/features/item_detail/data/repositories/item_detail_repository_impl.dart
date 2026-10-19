import '../../domain/entities/item_detail.dart';
import '../../domain/repositories/item_detail_repository.dart';
import '../datasources/item_detail_remote_data_source.dart';

class ItemDetailRepositoryImpl implements ItemDetailRepository {
  const ItemDetailRepositoryImpl(this.remoteDataSource);

  final ItemDetailRemoteDataSource remoteDataSource;

  @override
  Future<ItemDetail> setVisibility(int itemId, {required bool hidden}) async {
    try {
      return await remoteDataSource.setVisibility(itemId, hidden: hidden);
    } on ItemDetailRemoteException catch (error) {
      throw ItemDetailException(error.message);
    }
  }

  @override
  Future<void> delete(int itemId) async {
    try {
      await remoteDataSource.delete(itemId);
    } on ItemDetailRemoteException catch (error) {
      throw ItemDetailException(error.message);
    }
  }

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
