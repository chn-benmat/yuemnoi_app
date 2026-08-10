import '../../domain/entities/auth_tokens.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

// คำอธิบาย: คลาสอิมพลีเมนต์ (Implementation) ของ AuthRepository ทำหน้าที่ประสานงานกับ Data Source
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl(this.remoteDataSource);

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final tokens = await remoteDataSource.login(
      email: email,
      password: password,
    );
    return AuthTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  @override
  Future<void> register({
    required String displayName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
    required List<int>? imageBytes,
    required String? imageFileName,
  }) {
    return remoteDataSource.register(
      displayName: displayName,
      email: email,
      phone: phone,
      password: password,
      confirmPassword: confirmPassword,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
    );
  }

  @override
  Future<AuthTokens> verifyOtp({
    required String email,
    required String otpCode,
  }) async {
    final tokens = await remoteDataSource.verifyOtp(
      email: email,
      otpCode: otpCode,
    );
    return AuthTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  @override
  Future<void> sendOtp({
    required String email,
  }) {
    return remoteDataSource.sendOtp(email: email);
  }

  @override
  Future<void> changePassword({
    required String accessToken,
    required String newPassword,
  }) {
    return remoteDataSource.changePassword(
      accessToken: accessToken,
      newPassword: newPassword,
    );
  }

  @override
  Future<String> syncGoogleProfileImage({
    required String accessToken,
  }) {
    return remoteDataSource.syncGoogleProfileImage(
      accessToken: accessToken,
    );
  }

  @override
  void close() {
    remoteDataSource.close();
  }
}
