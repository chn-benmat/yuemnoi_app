import '../../domain/entities/rental_booking.dart';
import '../../domain/entities/rental_handover_code.dart';
import '../../domain/entities/rental_income.dart';
import '../../domain/repositories/rental_management_repository.dart';
import '../datasources/rental_management_remote_data_source.dart';

// คำอธิบาย: Implementation ของ RentalManagementRepository ในชั้น Data
class RentalManagementRepositoryImpl
    implements RentalManagementRepository, RentalHandoverRepository {
  final RentalManagementRemoteDataSource remoteDataSource;

  RentalManagementRepositoryImpl({
    RentalManagementRemoteDataSource? remoteDataSource,
  }) : remoteDataSource =
           remoteDataSource ?? RentalManagementRemoteDataSource();

  @override
  Future<List<RentalBooking>> getRentingBookings(String userId) async {
    final models = await remoteDataSource.getRentingBookings(userId);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<RentalBooking>> getLendingBookings(String userId) async {
    final models = await remoteDataSource.getLendingBookings(userId);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<RentalBooking>> getRentalHistory(String userId) async {
    final models = await remoteDataSource.getRentalHistory(userId);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<RentalHandoverCode> createHandoverCode({required int bookingId}) {
    return remoteDataSource.createHandoverCode(bookingId: bookingId);
  }

  @override
  Future<void> completeHandover({
    required int bookingId,
    required String code,
  }) {
    return remoteDataSource.completeHandover(bookingId: bookingId, code: code);
  }

  @override
  Future<void> updateBookingStatus({
    required int bookingId,
    required String status,
  }) {
    return remoteDataSource.updateBookingStatus(
      bookingId: bookingId,
      status: status,
    );
  }

  @override
  Future<RentalIncomeSummary> getRentalIncome(String userId) {
    return remoteDataSource.getRentalIncome(userId);
  }
}
