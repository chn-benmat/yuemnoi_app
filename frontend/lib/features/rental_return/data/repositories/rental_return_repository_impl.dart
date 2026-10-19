import '../../domain/entities/rental_return_session.dart';
import '../../domain/repositories/rental_return_repository.dart';
import '../datasources/rental_return_remote_data_source.dart';

class RentalReturnRepositoryImpl implements RentalReturnRepository {
  final RentalReturnRemoteDataSource _remoteDataSource;

  RentalReturnRepositoryImpl({RentalReturnRemoteDataSource? remoteDataSource})
    : _remoteDataSource = remoteDataSource ?? RentalReturnRemoteDataSource();

  @override
  Future<RentalReturnSession> getReturnSession([int? rentalId]) {
    return _remoteDataSource.getSession(rentalId);
  }

  @override
  Future<String> uploadInspectionPhoto({
    required int rentalId,
    required String photoPath,
    required String angleKey,
    required String challengeCode,
  }) {
    return _remoteDataSource.uploadPhoto(
      rentalId: rentalId,
      photoPath: photoPath,
      angleKey: angleKey,
    );
  }

  @override
  Future<void> submitConditionVerification({
    required int rentalId,
    required List<ReturnInspectionPhoto> photos,
    required Map<String, bool> checklist,
  }) {
    return _remoteDataSource.submitVerification(
      rentalId: rentalId,
      photos: photos,
      checklist: checklist,
    );
  }

  @override
  Future<String> confirmMerchantReceipt({
    required int rentalId,
    required String merchantId,
  }) async {
    final result = await _remoteDataSource.generateMerchantToken(rentalId);
    return result['token'] ?? '';
  }

  @override
  Future<bool> completeReturnWithToken({
    required int rentalId,
    required String tokenOrOtp,
  }) async {
    // ตรวจสอบว่า token หรือ otp มีรูปแบบถูกต้อง
    final isValid =
        tokenOrOtp.contains('YUEMNOI_RETURN_$rentalId') ||
        (tokenOrOtp.length == 6 && int.tryParse(tokenOrOtp) != null);

    if (isValid) {
      await _remoteDataSource.markCompleted(rentalId);
      return true;
    }
    return false;
  }
}
