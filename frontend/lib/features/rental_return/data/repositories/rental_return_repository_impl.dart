import '../../domain/entities/rental_return_session.dart';
import '../../domain/repositories/rental_return_repository.dart';
import '../datasources/rental_return_remote_data_source.dart';

class RentalReturnRepositoryImpl implements RentalReturnRepository {
  final RentalReturnRemoteDataSource _remoteDataSource;

  RentalReturnRepositoryImpl({RentalReturnRemoteDataSource? remoteDataSource})
    : _remoteDataSource = remoteDataSource ?? RentalReturnRemoteDataSource();

  @override
  Future<RentalReturnSession> getReturnSession([int? rentalId]) {
    return _remoteDataSource.getSession(rentalId);
  }

  @override
  Future<void> confirmMerchantReceipt({
    required int rentalId,
    bool pauseItem = false,
  }) {
    return _remoteDataSource.confirmReceipt(rentalId, pauseItem: pauseItem);
  }

  @override
  Future<RentalReturnPenaltyReport> savePenaltyReport({
    required int rentalId,
    required bool damaged,
    required bool late,
    required String details,
  }) => _remoteDataSource.savePenaltyReport(
    rentalId: rentalId,
    damaged: damaged,
    late: late,
    details: details,
  );

  @override
  Future<String> getPenaltyQr(int rentalId) =>
      _remoteDataSource.getPenaltyQr(rentalId);
}
