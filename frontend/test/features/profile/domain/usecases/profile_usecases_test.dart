import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/entities/user_profile.dart';
import 'package:frontend/features/profile/domain/repositories/profile_repository.dart';
import 'package:frontend/features/profile/domain/usecases/change_profile_password_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/get_user_profile_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/update_contact_phone_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/update_user_profile_usecase.dart';

class FakeProfileRepository implements ProfileRepository {
  UserProfile profile = const UserProfile(
    userId: 'u1',
    displayName: 'Old Name',
    username: 'olduser',
    email: 'user@test.com',
    phone: '0811111111',
  );

  bool passwordChanged = false;

  @override
  UserProfile? readCachedProfile(String userId) => null;

  @override
  Future<UserProfile> getProfile({
    required String userId,
    String? accessToken,
  }) async {
    return profile;
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
    profile = profile.copyWith(
      displayName: displayName,
      username: username,
      bio: bio,
    );
    return profile;
  }

  @override
  Future<void> updateContactPhone({
    required String accessToken,
    required String phone,
  }) async {
    profile = profile.copyWith(phone: phone);
  }

  @override
  Future<void> changePassword({
    required String accessToken,
    required String newPassword,
  }) async {
    passwordChanged = true;
  }
}

void main() {
  late FakeProfileRepository repository;

  setUp(() {
    repository = FakeProfileRepository();
  });

  test('GetUserProfileUseCase returns user profile', () async {
    final useCase = GetUserProfileUseCase(repository);
    final result = await useCase.execute(userId: 'u1');

    expect(result.userId, 'u1');
    expect(result.displayName, 'Old Name');
  });

  test('UpdateUserProfileUseCase updates profile data', () async {
    final useCase = UpdateUserProfileUseCase(repository);
    final result = await useCase.execute(
      accessToken: 'token123',
      displayName: 'New Name',
      username: 'newuser',
      bio: 'New bio',
    );

    expect(result.displayName, 'New Name');
    expect(result.username, 'newuser');
    expect(result.bio, 'New bio');
  });

  test('UpdateContactPhoneUseCase updates phone', () async {
    final useCase = UpdateContactPhoneUseCase(repository);
    await useCase.execute(accessToken: 'token123', phone: '0899999999');

    expect(repository.profile.phone, '0899999999');
  });

  test('ChangeProfilePasswordUseCase changes password', () async {
    final useCase = ChangeProfilePasswordUseCase(repository);
    await useCase.execute(
      accessToken: 'token123',
      newPassword: 'newPassword123',
    );

    expect(repository.passwordChanged, isTrue);
  });
}
