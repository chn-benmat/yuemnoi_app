import '../repositories/wallet_repository.dart';

class PayRentalWithWalletUseCase {
  const PayRentalWithWalletUseCase(this._repository);

  final WalletRepository _repository;

  Future<bool> execute(int rentalId) =>
      _repository.payRentalWithWallet(rentalId: rentalId);
}
