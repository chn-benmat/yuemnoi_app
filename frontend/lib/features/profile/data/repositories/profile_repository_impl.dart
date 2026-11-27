import '../../../../core/cache/app_cache.dart';
import '../../../../core/network/auth_session.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_data_source.dart';
import '../models/user_profile_model.dart';

// คำอธิบาย: Implementation ของ ProfileRepository ในชั้น Data
class ProfileRepositoryImpl implements ProfileRepository {
  static const _cacheNamespace = 'profile';
  static const _cacheKey = 'account';

  final ProfileRemoteDataSource remoteDataSource;

  ProfileRepositoryImpl({ProfileRemoteDataSource? remoteDataSource})
    : remoteDataSource = remoteDataSource ?? ProfileRemoteDataSource();

  @override
  UserProfile? readCachedProfile(String userId) {
    final rows = AppCache.readMemorySnapshot(
      _cacheNamespace,
      _cacheKey,
      userId,
    );
    return rows == null
        ? null
        : UserProfileModel.fromJson(rows.single).toEntity();
  }

  void _rememberProfile(UserProfileModel profile, String userId, int revision) {
    if (profile.userId != userId ||
        profile.username.isEmpty ||
        AppCache.scopeRevision(userId) != revision) {
      return;
    }
    AppCache.rememberSnapshot(_cacheNamespace, _cacheKey, userId, [
      profile.toJson(),
    ]);
  }

  @override
  Future<UserProfile> getProfile({
    required String userId,
    String? accessToken,
  }) async {
    final revision = AppCache.scopeRevision(userId);
    final snapshot = AppCache.readMemorySnapshot(
      _cacheNamespace,
      _cacheKey,
      userId,
    );
    final model = await remoteDataSource.getProfile(
      userId: userId,
      accessToken: accessToken,
    );
    // คำขอที่เริ่มก่อนบันทึกไม่ควรเขียนทับชื่อใหม่ในแคช
    if (accessToken != null &&
        accessToken.isNotEmpty &&
        identical(
          snapshot,
          AppCache.readMemorySnapshot(_cacheNamespace, _cacheKey, userId),
        )) {
      _rememberProfile(model, userId, revision);
    }
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
    final userId = AuthSession.userId;
    final revision = userId == null ? null : AppCache.scopeRevision(userId);
    final model = await remoteDataSource.updateProfile(
      accessToken: accessToken,
      displayName: displayName,
      username: username,
      bio: bio,
      imageBytes: imageBytes,
      imageName: imageName,
    );
    if (userId != null && userId == AuthSession.userId) {
      _rememberProfile(model, userId, revision!);
    }
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
