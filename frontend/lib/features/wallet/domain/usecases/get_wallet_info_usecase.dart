import '../entities/wallet_info.dart';
import '../repositories/wallet_repository.dart';

class GetWalletInfoUseCase {
  const GetWalletInfoUseCase(this._repository);

  final WalletRepository _repository;

  Future<WalletInfo> execute() => _repository.getWalletInfo();
}
