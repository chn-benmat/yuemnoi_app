import '../entities/user_profile.dart';
import '../repositories/profile_repository.dart';

// คำอธิบาย: UseCase สำหรับอัปเดตข้อมูลโปรไฟล์ผู้ใช้ (ชื่อ, username, bio, รูปโปรไฟล์)
class UpdateUserProfileUseCase {
  final ProfileRepository repository;

  const UpdateUserProfileUseCase(this.repository);

  Future<UserProfile> execute({
    required String accessToken,
    String? displayName,
    String? username,
    String? bio,
    List<int>? imageBytes,
    String? imageName,
  }) {
    return repository.updateProfile(
      accessToken: accessToken,
      displayName: displayName,
      username: username,
      bio: bio,
      imageBytes: imageBytes,
      imageName: imageName,
    );
  }
}
