import '../repositories/auth_repository.dart';

// คำอธิบาย: คลาส UseCase สำหรับจัดการขั้นตอนการเปลี่ยนรหัสผ่านใหม่
class ChangePasswordUseCase {
  final AuthRepository repository;

  ChangePasswordUseCase(this.repository);

  Future<void> execute({
    required String accessToken,
    required String newPassword,
  }) {
    return repository.changePassword(
      accessToken: accessToken,
      newPassword: newPassword,
    );
  }
}
