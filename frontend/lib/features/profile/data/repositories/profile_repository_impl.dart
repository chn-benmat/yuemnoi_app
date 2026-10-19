import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_data_source.dart';

// คำอธิบาย: Implementation ของ ProfileRepository ในชั้น Data
class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;

  ProfileRepositoryImpl({ProfileRemoteDataSource? remoteDataSource})
    : remoteDataSource = remoteDataSource ?? ProfileRemoteDataSource();

  @override
  Future<UserProfile> getProfile({
    required String userId,
    String? accessToken,
  }) async {
    final model = await remoteDataSource.getProfile(
      userId: userId,
      accessToken: accessToken,
    );
    return model.toEntity();
  }

  @override
  Future<UserProfile> updateProfile({
    required String accessToken,
    String? displayName,
    String? username,
    String? bio,
    List<int>? imageBytes,
    String? imageName,
  }) async {
    final model = await remoteDataSource.updateProfile(
      accessToken: accessToken,
      displayName: displayName,
      username: username,
      bio: bio,
      imageBytes: imageBytes,
      imageName: imageName,
    );
    return model.toEntity();
  }

  @override
  Future<void> updateContactPhone({
    required String accessToken,
    required String phone,
  }) {
    return remoteDataSource.updateContactPhone(
      accessToken: accessToken,
      phone: phone,
    );
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
}
