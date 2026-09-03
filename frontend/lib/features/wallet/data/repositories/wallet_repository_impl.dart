import '../../domain/entities/wallet_info.dart';
import '../../domain/entities/wallet_top_up_checkout.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../datasources/wallet_remote_data_source.dart';

class WalletRepositoryImpl implements WalletRepository {
  WalletRepositoryImpl(this._remoteDataSource);

  final WalletRemoteDataSource _remoteDataSource;

  @override
  Future<WalletInfo> getWalletInfo() async {
    try {
      return await _remoteDataSource.getWalletInfo();
    } on WalletRemoteException catch (e) {
      throw WalletException(e.message);
    } catch (_) {
      throw const WalletException('ไม่สามารถดึงข้อมูลกระเป๋าเงินได้');
    }
  }

  @override
  Future<WalletTopUpCheckout> startTopUp({required double amount}) async {
    try {
      return await _remoteDataSource.startTopUp(amount: amount);
    } on WalletRemoteException catch (e) {
      throw WalletException(e.message);
    } catch (_) {
      throw const WalletException('ไม่สามารถเริ่มต้นการเติมเงินผ่าน Stripe ได้');
    }
  }

  @override
  Future<bool> payRentalWithWallet({required int rentalId}) async {
    try {
      return await _remoteDataSource.payRentalWithWallet(rentalId: rentalId);
    } on WalletRemoteException catch (e) {
      throw WalletException(e.message);
    } catch (_) {
      throw const WalletException('ไม่สามารถชำระเงินด้วยกระเป๋าเงินได้');
    }
  }

  @override
  void close() {
    _remoteDataSource.close();
  }
}
