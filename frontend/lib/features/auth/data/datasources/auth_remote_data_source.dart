import '../../../../core/network/api_client.dart';

const invalidOtpMessage = 'รหัส OTP ผิด กรุณาลองใส่ใหม่';
const expiredOtpMessage = 'รหัส OTP หมดอายุ';

String otpVerificationMessageForDisplay(
  String apiMessage, {
  required bool hasExpired,
}) {
  if (apiMessage == invalidOtpMessage || apiMessage == expiredOtpMessage) {
    return hasExpired ? expiredOtpMessage : invalidOtpMessage;
  }

  return apiMessage;
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LoginTokens {
  const LoginTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

class AuthRemoteDataSource {
  AuthRemoteDataSource({ApiClient? client})
    : _client = client ?? DioApiClient();

  static const _loginPath = '/api/v1/auth/login';
  static const _registerPath = '/api/v1/auth/register';
  static const _sendOtpPath = '/api/v1/auth/send-otp';
  static const _verifyOtpPath = '/api/v1/auth/verify-otp';
  static const _changePasswordPath = '/api/v1/auth/change-password';
  static const _googleProfilePath = '/api/v1/auth/google-profile';

  final ApiClient _client;

  Future<String> register({
    required String displayName,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
    List<int>? imageBytes,
    String? imageFileName,
  }) async {
    try {
      final files = imageBytes == null || imageBytes.isEmpty
          ? const <ApiUpload>[]
          : <ApiUpload>[
              ApiUpload(
                fieldName: 'image',
                bytes: imageBytes,
                fileName: imageFileName ?? 'profile.jpg',
              ),
            ];
      final response = await _client.postMultipart(
        _registerPath,
        fields: {
          'display_name': displayName.trim(),
          'email': email.trim(),
          'phone': phone.trim(),
          'password': password,
          'confirm_password': confirmPassword,
        },
        files: files,
      );
      final body = _map(response.data);

      if (response.statusCode == 201) {
        final userId = body['user_id'];
        if (userId is String && userId.isNotEmpty) {
          return userId;
        }

        throw const AuthApiException(
          'เซิร์ฟเวอร์ตอบกลับสำเร็จ แต่ไม่พบรหัสผู้ใช้',
        );
      }

      throw AuthApiException(
        _errorMessage(body) ?? _registerErrorMessage(response.statusCode),
      );
    } on ApiClientException catch (error) {
      throw _requestException(error);
    }
  }

  Future<LoginTokens> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        _loginPath,
        data: {'email': email.trim(), 'password': password},
      );
      final body = _map(response.data);

      if (response.statusCode == 200) {
        final accessToken = body['access_token'];
        final refreshToken = body['refresh_token'];
        if (accessToken is String &&
            accessToken.isNotEmpty &&
            refreshToken is String &&
            refreshToken.isNotEmpty) {
          return LoginTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
        }

        throw const AuthApiException(
          'เซิร์ฟเวอร์ตอบกลับสำเร็จ แต่ข้อมูล Session ไม่ครบถ้วน',
        );
      }

      throw AuthApiException(
        _errorMessage(body) ?? _defaultErrorMessage(response.statusCode),
      );
    } on ApiClientException catch (error) {
      throw _requestException(error);
    }
  }

  Future<void> sendOtp({required String email}) async {
    try {
      final response = await _client.post(
        _sendOtpPath,
        data: {'email': email.trim()},
      );
      final body = _map(response.data);

      if (response.statusCode == 200) {
        return;
      }

      if (response.statusCode == 404) {
        throw const AuthApiException('ไม่พบอีเมล');
      }

      throw AuthApiException(
        _errorMessage(body) ?? _sendOtpErrorMessage(response.statusCode),
      );
    } on ApiClientException catch (error) {
      throw _requestException(error);
    }
  }

  Future<LoginTokens> verifyOtp({
    required String email,
    required String otpCode,
  }) async {
    try {
      final response = await _client.post(
        _verifyOtpPath,
        data: {'email': email.trim(), 'otp_code': otpCode},
      );
      final body = _map(response.data);

      if (response.statusCode == 200) {
        final accessToken = body['access_token'];
        final refreshToken = body['refresh_token'];
        if (accessToken is String && accessToken.isNotEmpty) {
          return LoginTokens(
            accessToken: accessToken,
            refreshToken: refreshToken is String ? refreshToken : '',
          );
        }

        throw const AuthApiException('ยืนยัน OTP สำเร็จ แต่ไม่พบ Access Token');
      }

      throw AuthApiException(_verifyOtpErrorMessage(response.statusCode, body));
    } on ApiClientException catch (error) {
      throw _requestException(error);
    }
  }

  Future<void> changePassword({
    required String accessToken,
    required String newPassword,
  }) async {
    try {
      final response = await _client.post(
        _changePasswordPath,
        data: {'new_password': newPassword},
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      final body = _map(response.data);
      if (response.statusCode == 200) {
        return;
      }

      throw AuthApiException(
        _changePasswordErrorMessage(response.statusCode, body),
      );
    } on ApiClientException catch (error) {
      throw _requestException(error);
    }
  }

  Future<String> syncGoogleProfileImage({required String accessToken}) async {
    try {
      final response = await _client.post(
        _googleProfilePath,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      final body = _map(response.data);
      if (response.statusCode == 200) {
        final imageURL = body['user_image_url'];
        if (imageURL is String && imageURL.isNotEmpty) {
          return imageURL;
        }

        throw const AuthApiException(
          'บันทึกรูปโปรไฟล์ Google สำเร็จ แต่ไม่พบ URL รูปโปรไฟล์',
        );
      }

      throw AuthApiException(
        _errorMessage(body) ?? 'ไม่สามารถบันทึกรูปโปรไฟล์ Google ได้',
      );
    } on ApiClientException catch (error) {
      throw _requestException(
        error,
        timeoutMessage:
            'การบันทึกรูปโปรไฟล์ Google ใช้เวลานานเกินไป กรุณาลองใหม่',
        connectionMessage:
            'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์เพื่อบันทึกรูปโปรไฟล์ Google ได้',
      );
    }
  }

  AuthApiException _requestException(
    ApiClientException error, {
    String timeoutMessage = 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง',
    String connectionMessage =
        'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาตรวจสอบอินเทอร์เน็ต',
  }) {
    switch (error.type) {
      case ApiClientErrorType.timeout:
        return AuthApiException(timeoutMessage);
      case ApiClientErrorType.connection:
        return AuthApiException(connectionMessage);
      case ApiClientErrorType.invalidResponse:
        return const AuthApiException('ข้อมูลตอบกลับจากเซิร์ฟเวอร์ไม่ถูกต้อง');
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String? _errorMessage(Map<String, dynamic> body) {
    final message = body['error'] ?? body['message'];
    return message is String && message.isNotEmpty ? message : null;
  }

  String _defaultErrorMessage(int statusCode) {
    if (statusCode == 401) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }
    if (statusCode >= 500) {
      return 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่ภายหลัง';
    }
    return 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _registerErrorMessage(int statusCode) {
    if (statusCode == 409) {
      return 'อีเมลนี้ถูกใช้งานแล้ว กรุณาใช้อีเมลอื่น';
    }
    if (statusCode >= 500) {
      return 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่ภายหลัง';
    }
    return 'สมัครสมาชิกไม่สำเร็จ กรุณาตรวจสอบข้อมูลแล้วลองใหม่';
  }

  String _sendOtpErrorMessage(int statusCode) {
    if (statusCode >= 500) {
      return 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่ภายหลัง';
    }
    return 'ส่งรหัส OTP ไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _verifyOtpErrorMessage(int statusCode, Map<String, dynamic> body) {
    if (statusCode >= 500) {
      return 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่ภายหลัง';
    }

    final backendMessage = _errorMessage(body);
    final normalizedMessage = backendMessage?.toLowerCase() ?? '';

    if (normalizedMessage.contains('otp_expired') ||
        normalizedMessage.contains('expired') ||
        normalizedMessage.contains('หมดอายุ')) {
      return expiredOtpMessage;
    }

    if (statusCode == 400 ||
        statusCode == 422 ||
        normalizedMessage.contains('invalid')) {
      return invalidOtpMessage;
    }

    return backendMessage ?? 'ยืนยันรหัส OTP ไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _changePasswordErrorMessage(
    int statusCode,
    Map<String, dynamic> body,
  ) {
    final backendMessage = _errorMessage(body);
    final normalizedMessage = backendMessage?.toLowerCase() ?? '';

    if (statusCode == 401 ||
        statusCode == 403 ||
        normalizedMessage.contains('bad_jwt') ||
        normalizedMessage.contains('invalid jwt') ||
        normalizedMessage.contains('jwt expired') ||
        normalizedMessage.contains('session_not_found')) {
      return 'เซสชันหมดอายุ กรุณายืนยันตัวตนใหม่อีกครั้ง';
    }

    if (normalizedMessage.contains('same_password')) {
      return 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านที่ใช้อยู่ในปัจจุบัน';
    }

    if (normalizedMessage.contains('weak_password') ||
        normalizedMessage.contains('password should be at least') ||
        normalizedMessage.contains('password is too weak')) {
      return 'รหัสผ่านใหม่ไม่ผ่านเงื่อนไขความปลอดภัย กรุณาใช้รหัสผ่านที่คาดเดายากขึ้น';
    }

    if (statusCode >= 500) {
      return backendMessage ?? 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่ภายหลัง';
    }
    return backendMessage ?? 'เปลี่ยนรหัสผ่านไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  void close() {
    _client.close();
  }
}
