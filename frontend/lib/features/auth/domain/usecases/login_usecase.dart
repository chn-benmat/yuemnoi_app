import '../entities/auth_tokens.dart';
import '../repositories/auth_repository.dart';

// คำอธิบาย: คลาส UseCase สำหรับจัดการขั้นตอนการทำงานเข้าสู่ระบบด้วยอีเมลและรหัสผ่าน
class LoginUseCase {
  final AuthRepository repository;

  LoginUseCase(this.repository);

  Future<AuthTokens> execute({
    required String email,
    required String password,
  }) {
    return repository.login(email: email, password: password);
  }
}
