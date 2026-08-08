import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/features/auth/data/datasources/auth_remote_data_source.dart';

void main() {
  test('verifyOtp shows an invalid message when the OTP is wrong', () async {
    final dataSource = AuthRemoteDataSource(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'error': 'invalid OTP code'})),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(dataSource.close);

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
    final dataSource = AuthRemoteDataSource(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'error':
                  'การยืนยันรหัส OTP ล้มเหลว หรือรหัสหมดอายุ: '
                  'invalid or expired OTP code: otp_expired',
            }),
          ),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(dataSource.close);

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
    final dataSource = AuthRemoteDataSource(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'temporary-access-token',
            'refresh_token': 'temporary-refresh-token',
          }),
          200,
        ),
      ),
    );
    addTearDown(dataSource.close);

    final tokens = await dataSource.verifyOtp(
      email: 'user@example.com',
      otpCode: '123456',
    );

    expect(tokens.accessToken, 'temporary-access-token');
    expect(tokens.refreshToken, 'temporary-refresh-token');
  });

  test('changePassword sends the new password with the bearer token', () async {
    late http.Request capturedRequest;
    final dataSource = AuthRemoteDataSource(
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode({'status': 200}), 200);
      }),
    );
    addTearDown(dataSource.close);

    await dataSource.changePassword(
      accessToken: 'temporary-access-token',
      newPassword: 'new-password',
    );

    expect(
      capturedRequest.url.toString(),
      'https://my-computer.tail38bb18.ts.net/api/v1/auth/change-password',
    );
    expect(
      capturedRequest.headers['authorization'],
      'Bearer temporary-access-token',
    );
    expect(jsonDecode(capturedRequest.body), {'new_password': 'new-password'});
  });

  test('changePassword translates an invalid Supabase session', () async {
    final dataSource = AuthRemoteDataSource(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error':
                'เปลี่ยนรหัสผ่านไม่สำเร็จ: supabase update password failed: bad_jwt: invalid JWT',
          }),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(dataSource.close);

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
    late http.Request capturedRequest;
    final dataSource = AuthRemoteDataSource(
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'status': 200,
            'user_image_url': 'https://lh3.googleusercontent.com/a/avatar',
          }),
          200,
        );
      }),
    );
    addTearDown(dataSource.close);

    final imageURL = await dataSource.syncGoogleProfileImage(
      accessToken: 'google-access-token',
    );

    expect(
      capturedRequest.url.toString(),
      'https://my-computer.tail38bb18.ts.net/api/v1/auth/google-profile',
    );
    expect(
      capturedRequest.headers['authorization'],
      'Bearer google-access-token',
    );
    expect(imageURL, 'https://lh3.googleusercontent.com/a/avatar');
  });

  test('changePassword explains when the password is unchanged', () async {
    final dataSource = AuthRemoteDataSource(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error':
                'supabase update password failed: same_password: New password should be different',
          }),
          500,
        ),
      ),
    );
    addTearDown(dataSource.close);

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
}
