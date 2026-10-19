import '../entities/auth_tokens.dart';
import '../repositories/auth_repository.dart';

// คำอธิบาย: คลาส UseCase สำหรับจัดการขั้นตอนการยืนยันรหัส OTP
class VerifyOtpUseCase {
  final AuthRepository repository;

  VerifyOtpUseCase(this.repository);

  Future<AuthTokens> execute({required String email, required String otpCode}) {
    return repository.verifyOtp(email: email, otpCode: otpCode);
  }
}
