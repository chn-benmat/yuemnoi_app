import '../repositories/auth_repository.dart';

class GoogleLoginUseCase {
  const GoogleLoginUseCase(this._repository);

  final AuthRepository _repository;

  Future<bool> execute() => _repository.loginWithGoogle();
}
