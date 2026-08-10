// คำอธิบาย: คลาสเอนทิตี (Entity) สำหรับเก็บค่า Token ที่ได้รับเมื่อเข้าสู่ระบบสำเร็จ
class AuthTokens {
  final String accessToken;
  final String refreshToken;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });
}
