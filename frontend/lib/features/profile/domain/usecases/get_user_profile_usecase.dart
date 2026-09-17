import '../entities/user_profile.dart';
import '../repositories/profile_repository.dart';

// คำอธิบาย: UseCase สำหรับดึงข้อมูลโปรไฟล์ผู้ใช้
class GetUserProfileUseCase {
  final ProfileRepository repository;

  const GetUserProfileUseCase(this.repository);

  Future<UserProfile> execute({
    required String userId,
    String? accessToken,
  }) {
    return repository.getProfile(
      userId: userId,
      accessToken: accessToken,
    );
  }
}
