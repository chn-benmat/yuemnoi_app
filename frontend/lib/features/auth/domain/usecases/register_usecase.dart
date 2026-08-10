import '../repositories/auth_repository.dart';

// คำอธิบาย: คลาส UseCase สำหรับจัดการขั้นตอนการลงทะเบียนสมัครสมาชิกใหม่
class RegisterUseCase {
  final AuthRepository repository;

  RegisterUseCase(this.repository);

  Future<void> execute({
    required String displayName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
    required List<int>? imageBytes,
    required String? imageFileName,
  }) {
    return repository.register(
      displayName: displayName,
      email: email,
      phone: phone,
      password: password,
      confirmPassword: confirmPassword,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
    );
  }
}
