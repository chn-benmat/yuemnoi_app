import '../repositories/profile_repository.dart';

// คำอธิบาย: UseCase สำหรับอัปเดตเบอร์โทรศัพท์ติดต่อของผู้ใช้
class UpdateContactPhoneUseCase {
  final ProfileRepository repository;

  const UpdateContactPhoneUseCase(this.repository);

  Future<void> execute({
    required String accessToken,
    required String phone,
  }) {
    return repository.updateContactPhone(
      accessToken: accessToken,
      phone: phone,
    );
  }
}
