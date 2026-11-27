import '../entities/user_profile.dart';

// คำอธิบาย: สัญญา (Contract) การทำงานเกี่ยวกับการจัดการโปรไฟล์และบัญชีผู้ใช้ในชั้น Domain
abstract class ProfileRepository {
  UserProfile? readCachedProfile(String userId);

  Future<UserProfile> getProfile({required String userId, String? accessToken});

  Future<UserProfile> updateProfile({
    required String accessToken,
    String? displayName,
    String? username,
    String? bio,
    List<int>? imageBytes,
    String? imageName,
  });

  Future<void> updateContactPhone({
    required String accessToken,
    required String phone,
  });

  Future<void> changePassword({
    required String accessToken,
    required String newPassword,
  });
}
