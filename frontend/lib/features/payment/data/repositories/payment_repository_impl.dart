import '../../domain/entities/payment.dart';
import '../../domain/repositories/payment_repository.dart';
import '../datasources/payment_remote_data_source.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  const PaymentRepositoryImpl(this.remoteDataSource);

  final PaymentRemoteDataSource remoteDataSource;

  @override
  Future<PaymentCheckout> startCheckout(PaymentRentalDraft draft) async {
    try {
      return await remoteDataSource.startCheckout(draft);
    } on PaymentRemoteException catch (error) {
      throw PaymentException(error.message);
    }
  }

  @override
  Future<int> createRental(PaymentRentalDraft draft) async {
    try {
      return await remoteDataSource.createRental(draft);
    } on PaymentRemoteException catch (error) {
      throw PaymentException(error.message);
    }
  }

  @override
  Future<bool> payWithWallet(int rentalId) async {
    try {
      return await remoteDataSource.payWithWallet(rentalId);
    } on PaymentRemoteException catch (error) {
      throw PaymentException(error.message);
    }
  }

  @override
  Future<RentalPaymentStatus> getStatus(int rentalId) async {
    try {
      return await remoteDataSource.getStatus(rentalId);
    } on PaymentRemoteException catch (error) {
      throw PaymentException(error.message);
    }
  }

  @override
  void close() => remoteDataSource.close();
}
