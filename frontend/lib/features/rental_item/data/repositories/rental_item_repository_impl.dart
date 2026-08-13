import '../../domain/entities/rental_item.dart';
import '../../domain/repositories/rental_item_repository.dart';
import '../datasources/rental_item_remote_data_source.dart';

class RentalItemRepositoryImpl implements RentalItemRepository {
  const RentalItemRepositoryImpl(this.remoteDataSource);

  final RentalItemRemoteDataSource remoteDataSource;

  @override
  Future<RentalItem> create(RentalItemDraft draft) async {
    try {
      return await remoteDataSource.create(draft);
    } on RentalItemRemoteException catch (error) {
      throw RentalItemException(error.message);
    }
  }

  @override
  void close() => remoteDataSource.close();
}
