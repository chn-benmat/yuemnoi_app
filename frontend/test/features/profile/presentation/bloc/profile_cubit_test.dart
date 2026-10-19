import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/usecases/change_profile_password_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/get_user_profile_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/update_contact_phone_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/update_user_profile_usecase.dart';
import 'package:frontend/features/profile/presentation/bloc/profile_cubit.dart';
import 'package:frontend/features/profile/presentation/bloc/profile_state.dart';

import '../../domain/usecases/profile_usecases_test.dart';

ProfileCubit buildCubit(FakeProfileRepository repository) {
  return ProfileCubit(
    getUserProfile: GetUserProfileUseCase(repository),
    updateUserProfile: UpdateUserProfileUseCase(repository),
    updateContactPhone: UpdateContactPhoneUseCase(repository),
    changeProfilePassword: ChangeProfilePasswordUseCase(repository),
  );
}

void main() {
  group('ProfileCubit', () {
    test('initial state is ProfileInitial', () {
      final repository = FakeProfileRepository();
      final cubit = buildCubit(repository);
      expect(cubit.state, isA<ProfileInitial>());
      cubit.close();
    });

    blocTest<ProfileCubit, ProfileState>(
      'loadProfile emits [ProfileLoading, ProfileLoaded]',
      build: () => buildCubit(FakeProfileRepository()),
      act: (cubit) => cubit.loadProfile(userId: 'u1'),
      expect: () => [
        isA<ProfileLoading>(),
        isA<ProfileLoaded>().having(
          (s) => s.profile.displayName,
          'displayName',
          'Old Name',
        ),
      ],
    );

    blocTest<ProfileCubit, ProfileState>(
      'updateProfileData emits [ProfileActionInProgress, ProfileActionSuccess, ProfileLoaded]',
      build: () => buildCubit(FakeProfileRepository()),
      act: (cubit) => cubit.updateProfileData(
        accessToken: 'token123',
        displayName: 'Updated Name',
        bio: 'New Bio',
      ),
      expect: () => [
        isA<ProfileActionInProgress>(),
        isA<ProfileActionSuccess>(),
        isA<ProfileLoaded>().having(
          (s) => s.profile.displayName,
          'displayName',
          'Updated Name',
        ),
      ],
    );

    blocTest<ProfileCubit, ProfileState>(
      'updatePhone emits [ProfileActionInProgress, ProfileActionSuccess]',
      build: () => buildCubit(FakeProfileRepository()),
      act: (cubit) =>
          cubit.updatePhone(accessToken: 'token123', phone: '0855555555'),
      expect: () => [
        isA<ProfileActionInProgress>(),
        isA<ProfileActionSuccess>(),
      ],
    );

    blocTest<ProfileCubit, ProfileState>(
      'changeUserPassword emits [ProfileActionInProgress, ProfileActionSuccess]',
      build: () => buildCubit(FakeProfileRepository()),
      act: (cubit) => cubit.changeUserPassword(
        accessToken: 'token123',
        newPassword: 'newSecretPassword',
      ),
      expect: () => [
        isA<ProfileActionInProgress>(),
        isA<ProfileActionSuccess>(),
      ],
    );
  });
}
