import '../entities/wallet_top_up_checkout.dart';
import '../repositories/wallet_repository.dart';

class StartWalletTopUpUseCase {
  const StartWalletTopUpUseCase(this._repository);

  final WalletRepository _repository;

  Future<WalletTopUpCheckout> execute(double amount) =>
      _repository.startTopUp(amount: amount);
}
