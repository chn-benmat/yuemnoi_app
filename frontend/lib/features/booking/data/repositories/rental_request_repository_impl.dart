import '../../../../core/services/item_catalog_service.dart';
import '../../domain/entities/rental_request.dart';
import '../../domain/repositories/rental_request_repository.dart';
import '../datasources/rental_request_remote_data_source.dart';

class RentalRequestRepositoryImpl implements RentalRequestRepository {
  RentalRequestRepositoryImpl(this.remoteDataSource);

  final RentalRequestRemoteDataSource remoteDataSource;

  @override
  Future<RentalRequestResult> submit(RentalRequestDraft draft) async {
    try {
      return await remoteDataSource.submit(draft);
    } on RentalRequestRemoteException catch (error) {
      throw RentalRequestException(error.message);
    }
  }

  @override
  Future<RentalRequestResult> confirm({
    required int rentalId,
    required String offerMessageId,
    required String paymentMethod,
    int? requestRevision,
  }) async {
    try {
      final result = await remoteDataSource.confirm(
        rentalId: rentalId,
        offerMessageId: offerMessageId,
        paymentMethod: paymentMethod,
        requestRevision: requestRevision,
      );
      ItemCatalogService.instance.notifyChanged();
      return result;
    } on RentalRequestRemoteException catch (error) {
      throw RentalRequestException(error.message);
    }
  }

  @override
  void close() => remoteDataSource.close();
}
