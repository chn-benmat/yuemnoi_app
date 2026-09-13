import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;
  late AuthRemoteDataSource dataSource;

  setUp(() {
    client = MockApiClient();
    dataSource = AuthRemoteDataSource(client: client);
    when(() => client.close()).thenReturn(null);
  });

  tearDown(() {
    dataSource.close();
  });

  void stubPost(ApiResponse response) {
    when(
      () => client.post(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async => response);
  }

  test('verifyOtp shows an invalid message when the OTP is wrong', () async {
    stubPost(
      const ApiResponse(statusCode: 400, data: {'error': 'invalid OTP code'}),
    );

    expect(
      () => dataSource.verifyOtp(email: 'user@example.com', otpCode: '123456'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          'รหัส OTP ผิด กรุณาลองใส่ใหม่',
        ),
      ),
    );
  });

  test('verifyOtp shows an expired message when the OTP has expired', () async {
    stubPost(
      const ApiResponse(
        statusCode: 400,
        data: {
          'error':
              'การยืนยันรหัส OTP ล้มเหลว หรือรหัสหมดอายุ: '
              'invalid or expired OTP code: otp_expired',
        },
      ),
    );

    expect(
      () => dataSource.verifyOtp(email: 'user@example.com', otpCode: '123456'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          'รหัส OTP หมดอายุ',
        ),
      ),
    );
  });

  test('OTP rejection is shown as invalid while the timer is active', () {
    expect(
      otpVerificationMessageForDisplay(expiredOtpMessage, hasExpired: false),
      invalidOtpMessage,
    );
  });

  test('OTP rejection is shown as expired after the timer ends', () {
    expect(
      otpVerificationMessageForDisplay(invalidOtpMessage, hasExpired: true),
      expiredOtpMessage,
    );
  });

  test('verifyOtp returns the temporary access token', () async {
    stubPost(
      const ApiResponse(
        statusCode: 200,
        data: {
          'access_token': 'temporary-access-token',
          'refresh_token': 'temporary-refresh-token',
        },
      ),
    );

    final tokens = await dataSource.verifyOtp(
      email: 'user@example.com',
      otpCode: '123456',
    );

    expect(tokens.accessToken, 'temporary-access-token');
    expect(tokens.refreshToken, 'temporary-refresh-token');
  });

  test('changePassword sends the new password with the bearer token', () async {
    stubPost(const ApiResponse(statusCode: 200, data: {'status': 200}));

    await dataSource.changePassword(
      accessToken: 'temporary-access-token',
      newPassword: 'new-password',
    );

    final captured = verify(
      () => client.post(
        '/api/v1/auth/change-password',
        data: captureAny(named: 'data'),
        headers: captureAny(named: 'headers'),
      ),
    ).captured;

    expect(captured.first, {'new_password': 'new-password'});
    expect(captured.last, {'Authorization': 'Bearer temporary-access-token'});
  });

  test('changePassword translates an invalid Supabase session', () async {
    stubPost(
      const ApiResponse(
        statusCode: 500,
        data: {
          'error':
              'เปลี่ยนรหัสผ่านไม่สำเร็จ: supabase update password failed: '
              'bad_jwt: invalid JWT',
        },
      ),
    );

    expect(
      () => dataSource.changePassword(
        accessToken: 'invalid-token',
        newPassword: 'new-password',
      ),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          'เซสชันหมดอายุ กรุณายืนยันตัวตนใหม่อีกครั้ง',
        ),
      ),
    );
  });

  test('syncGoogleProfileImage sends the Google access token', () async {
    stubPost(
      const ApiResponse(
        statusCode: 200,
        data: {
          'status': 200,
          'user_image_url': 'https://lh3.googleusercontent.com/a/avatar',
        },
      ),
    );

    final imageURL = await dataSource.syncGoogleProfileImage(
      accessToken: 'google-access-token',
    );

    final capturedHeaders = verify(
      () => client.post(
        '/api/v1/auth/google-profile',
        data: any(named: 'data'),
        headers: captureAny(named: 'headers'),
      ),
    ).captured.single;
    expect(capturedHeaders, {'Authorization': 'Bearer google-access-token'});
    expect(imageURL, 'https://lh3.googleusercontent.com/a/avatar');
  });

  test('changePassword explains when the password is unchanged', () async {
    stubPost(
      const ApiResponse(
        statusCode: 500,
        data: {
          'error':
              'supabase update password failed: same_password: '
              'New password should be different',
        },
      ),
    );

    expect(
      () => dataSource.changePassword(
        accessToken: 'temporary-access-token',
        newPassword: 'same-password',
      ),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านที่ใช้อยู่ในปัจจุบัน',
        ),
      ),
    );
  });

  test('connection timeout is translated to a user-facing message', () async {
    when(
      () => client.post(
        any(),
        data: any(named: 'data'),
        headers: any(named: 'headers'),
      ),
    ).thenThrow(const ApiClientException(ApiClientErrorType.timeout));

    expect(
      () => dataSource.login(email: 'user@example.com', password: 'password'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง',
        ),
      ),
    );
  });
}
