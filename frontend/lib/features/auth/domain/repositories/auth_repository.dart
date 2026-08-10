import '../entities/auth_tokens.dart';

// คำอธิบาย: อินเตอร์เฟสกำหนดข้อตกลง (Contract) การทำงานเกี่ยวกับการยืนยันตัวตนในชั้น Domain
abstract class AuthRepository {
  Future<AuthTokens> login({
    required String email,
    required String password,
  });

  Future<void> register({
    required String displayName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
    required List<int>? imageBytes,
    required String? imageFileName,
  });

  Future<AuthTokens> verifyOtp({
    required String email,
    required String otpCode,
  });

  Future<void> sendOtp({
    required String email,
  });

  Future<void> changePassword({
    required String accessToken,
    required String newPassword,
  });

  Future<String> syncGoogleProfileImage({
    required String accessToken,
  });

  void close();
}
