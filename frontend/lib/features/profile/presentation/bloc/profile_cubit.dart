import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/profile_remote_data_source.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/usecases/change_profile_password_usecase.dart';
import '../../domain/usecases/get_user_profile_usecase.dart';
import '../../domain/usecases/update_contact_phone_usecase.dart';
import '../../domain/usecases/update_user_profile_usecase.dart';
import 'profile_state.dart';

// คำอธิบาย: Cubit สำหรับจัดการสถานะโปรไฟล์และข้อมูลบัญชีผู้ใช้ในชั้น Presentation
class ProfileCubit extends Cubit<ProfileState> {
  final GetUserProfileUseCase getUserProfile;
  final UpdateUserProfileUseCase updateUserProfile;
  final UpdateContactPhoneUseCase updateContactPhone;
  final ChangeProfilePasswordUseCase changeProfilePassword;

  UserProfile? _currentProfile;
  UserProfile? get currentProfile => _currentProfile;
  int _loadRevision = 0;

  ProfileCubit({
    GetUserProfileUseCase? getUserProfile,
    UpdateUserProfileUseCase? updateUserProfile,
    UpdateContactPhoneUseCase? updateContactPhone,
    ChangeProfilePasswordUseCase? changeProfilePassword,
  }) : getUserProfile =
           getUserProfile ?? GetUserProfileUseCase(ProfileRepositoryImpl()),
       updateUserProfile =
           updateUserProfile ??
           UpdateUserProfileUseCase(ProfileRepositoryImpl()),
       updateContactPhone =
           updateContactPhone ??
           UpdateContactPhoneUseCase(ProfileRepositoryImpl()),
       changeProfilePassword =
           changeProfilePassword ??
           ChangeProfilePasswordUseCase(ProfileRepositoryImpl()),
       super(const ProfileInitial());

  @override
  void emit(ProfileState state) {
    if (isClosed) return;
    super.emit(state);
  }

  Future<void> loadProfile({
    required String userId,
    String? accessToken,
  }) async {
    if (isClosed) return;
    final revision = ++_loadRevision;
    final cached = accessToken?.isNotEmpty == true
        ? getUserProfile.repository.readCachedProfile(userId)
        : null;
    if (cached != null && cached.userId == userId) {
      _currentProfile = cached;
    } else if (_currentProfile?.userId != userId) {
      _currentProfile = null;
    }
    emit(const ProfileLoading());
    try {
      final profile = await getUserProfile.execute(
        userId: userId,
        accessToken: accessToken,
      );
      if (isClosed || revision != _loadRevision) return;
      if (profile.userId != userId) {
        throw const ProfileApiException('โหลดโปรไฟล์ไม่สำเร็จ กรุณาลองใหม่');
      }
      _currentProfile = profile;
      emit(ProfileLoaded(profile));
    } catch (e) {
      if (isClosed || revision != _loadRevision) return;
      emit(
        ProfileActionFailure(
          message: e.toString(),
          currentProfile: _currentProfile,
        ),
      );
    }
  }

  Future<bool> updateProfileData({
    required String accessToken,
    String? displayName,
    String? username,
    String? bio,
    List<int>? imageBytes,
    String? imageName,
  }) async {
    emit(ProfileActionInProgress(currentProfile: _currentProfile));
    try {
      final updated = await updateUserProfile.execute(
        accessToken: accessToken,
        displayName: displayName,
        username: username,
        bio: bio,
        imageBytes: imageBytes,
        imageName: imageName,
      );
      if (isClosed) return false;
      _currentProfile = updated;
      emit(
        ProfileActionSuccess(
          message: 'บันทึกข้อมูลส่วนตัวเรียบร้อย',
          updatedProfile: updated,
        ),
      );
      emit(ProfileLoaded(updated));
      return true;
    } on ProfileApiException catch (e) {
      if (isClosed) return false;
      emit(
        ProfileActionFailure(
          message: e.message,
          currentProfile: _currentProfile,
        ),
      );
      return false;
    } catch (e) {
      if (isClosed) return false;
      emit(
        ProfileActionFailure(
          message: 'เกิดข้อผิดพลาดในการบันทึกข้อมูล: $e',
          currentProfile: _currentProfile,
        ),
      );
      return false;
    }
  }

  Future<bool> updatePhone({
    required String accessToken,
    required String phone,
  }) async {
    emit(ProfileActionInProgress(currentProfile: _currentProfile));
    try {
      await updateContactPhone.execute(accessToken: accessToken, phone: phone);
      if (isClosed) return false;
      if (_currentProfile != null) {
        _currentProfile = _currentProfile!.copyWith(phone: phone);
      }
      emit(
        ProfileActionSuccess(
          message: 'บันทึกข้อมูลติดต่อเรียบร้อย',
          updatedProfile: _currentProfile,
        ),
      );
      if (_currentProfile != null) {
        emit(ProfileLoaded(_currentProfile!));
      }
      return true;
    } on ProfileApiException catch (e) {
      if (isClosed) return false;
      emit(
        ProfileActionFailure(
          message: e.message,
          currentProfile: _currentProfile,
        ),
      );
      return false;
    } catch (e) {
      if (isClosed) return false;
      emit(
        ProfileActionFailure(
          message: 'เกิดข้อผิดพลาดในการบันทึกเบอร์โทร: $e',
          currentProfile: _currentProfile,
        ),
      );
      return false;
    }
  }

  Future<bool> changeUserPassword({
    required String accessToken,
    required String newPassword,
  }) async {
    emit(ProfileActionInProgress(currentProfile: _currentProfile));
    try {
      await changeProfilePassword.execute(
        accessToken: accessToken,
        newPassword: newPassword,
      );
      if (isClosed) return false;
      emit(
        ProfileActionSuccess(
          message: 'เปลี่ยนรหัสผ่านเรียบร้อย',
          updatedProfile: _currentProfile,
        ),
      );
      if (_currentProfile != null) {
        emit(ProfileLoaded(_currentProfile!));
      }
      return true;
    } on ProfileApiException catch (e) {
      if (isClosed) return false;
      emit(
        ProfileActionFailure(
          message: e.message,
          currentProfile: _currentProfile,
        ),
      );
      return false;
    } catch (e) {
      if (isClosed) return false;
      emit(
        ProfileActionFailure(
          message: 'เกิดข้อผิดพลาดในการเปลี่ยนรหัสผ่าน: $e',
          currentProfile: _currentProfile,
        ),
      );
      return false;
    }
  }
}
