import '../../domain/entities/user_profile.dart';

// คำอธิบาย: State ต่างๆ สำหรับการจัดการโปรไฟล์ในชั้น Presentation
abstract class ProfileState {
  const ProfileState();
}

class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

class ProfileLoaded extends ProfileState {
  final UserProfile profile;
  const ProfileLoaded(this.profile);
}

class ProfileActionInProgress extends ProfileState {
  final UserProfile? currentProfile;
  const ProfileActionInProgress({this.currentProfile});
}

class ProfileActionSuccess extends ProfileState {
  final String message;
  final UserProfile? updatedProfile;
  const ProfileActionSuccess({required this.message, this.updatedProfile});
}

class ProfileActionFailure extends ProfileState {
  final String message;
  final UserProfile? currentProfile;
  const ProfileActionFailure({required this.message, this.currentProfile});
}
