import '../entities/wallet_info.dart';
import '../entities/wallet_top_up_checkout.dart';

class WalletException implements Exception {
  const WalletException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class WalletRepository {
  Future<WalletInfo> getWalletInfo();
  Future<WalletTopUpCheckout> startTopUp({required double amount});
  Future<bool> payRentalWithWallet({required int rentalId});
  void close();
}
