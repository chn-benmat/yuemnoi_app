import '../repositories/auth_repository.dart';

// คำอธิบาย: คลาส UseCase สำหรับจัดการการดึงรูปภาพโปรไฟล์จากบัญชี Google เพื่อนำมาเซฟลงในระบบหลังบ้าน
class SyncGoogleProfileImageUseCase {
  final AuthRepository repository;

  SyncGoogleProfileImageUseCase(this.repository);

  Future<String> execute({
    required String accessToken,
  }) {
    return repository.syncGoogleProfileImage(
      accessToken: accessToken,
    );
  }
}
