import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/supabase_client.dart';

class GoogleAuthDataSource {
  GoogleAuthDataSource({GoTrueClient? auth, GoogleSignIn? googleSignIn})
    : _auth = auth,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  static final instance = GoogleAuthDataSource();

  final GoTrueClient? _auth;
  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  GoTrueClient get _authClient => _auth ?? SupabaseConfig.client.auth;

  Future<bool> login() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      final launched = await _authClient.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirectUrl,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        queryParams: const {'prompt': 'select_account'},
      );
      if (!launched) {
        throw const AuthException('ไม่สามารถเปิดหน้าล็อกอิน Google ได้');
      }
      return true;
    }

    final serverClientId = AppConfig.googleWebClientId;
    if (serverClientId.isEmpty) {
      throw const AuthException(
        'ยังไม่ได้ตั้งค่า GOOGLE_WEB_CLIENT_ID สำหรับ Google Login บน Android',
      );
    }

    try {
      await (_initialization ??= _initialize(serverClientId));

      // ล้างบัญชีที่เลือกไว้ เพื่อให้ผู้ใช้เลือกบัญชีใหม่ได้ทุกครั้งที่กดปุ่ม
      await _googleSignIn.signOut();
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          'ไม่พบข้อมูลยืนยันตัวตนจาก Google กรุณาลองใหม่',
        );
      }

      final response = await _authClient.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      if (response.session == null) {
        throw const AuthException('ไม่สามารถบันทึก Session จาก Google ได้');
      }
      return true;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return false;
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const AuthException(
          'การตั้งค่า Google Login ไม่ถูกต้อง กรุณาตรวจสอบ Android OAuth Client, '
          'SHA-1 และ GOOGLE_WEB_CLIENT_ID',
        );
      }
      throw const AuthException(
        'เข้าสู่ระบบด้วย Google ไม่สำเร็จ กรุณาลองใหม่',
      );
    }
  }

  Future<void> _initialize(String serverClientId) async {
    try {
      await _googleSignIn.initialize(serverClientId: serverClientId);
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }
}
