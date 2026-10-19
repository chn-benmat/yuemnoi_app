import '../repositories/auth_repository.dart';

// คำอธิบาย: คลาส UseCase สำหรับจัดการขั้นตอนการร้องขอรหัส OTP ทางอีเมล
class SendOtpUseCase {
  final AuthRepository repository;

  SendOtpUseCase(this.repository);

  Future<void> execute({required String email}) {
    return repository.sendOtp(email: email);
  }
}
