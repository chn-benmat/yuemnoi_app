import '../repositories/profile_repository.dart';

// คำอธิบาย: UseCase สำหรับเปลี่ยนรหัสผ่านในฟีเจอร์โปรไฟล์
class ChangeProfilePasswordUseCase {
  final ProfileRepository repository;

  const ChangeProfilePasswordUseCase(this.repository);

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
