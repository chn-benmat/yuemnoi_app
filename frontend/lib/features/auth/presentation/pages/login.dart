import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthApiException;
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../widgets/social_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authRemoteDataSource = AuthRemoteDataSource();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _signInHandled = false;
  StreamSubscription<AuthState>? _authStateSubscription;

  @override
  void initState() {
    super.initState();

    if (!SupabaseConfig.isInitialized) return;

    _authStateSubscription = SupabaseConfig.client.auth.onAuthStateChange
        .listen((authState) {
          if (authState.event == AuthChangeEvent.signedIn &&
              authState.session != null) {
            _completeSignIn(authState.session!);
          }
        }, onError: _handleAuthStateError);

    final existingSession = SupabaseConfig.client.auth.currentSession;
    if (existingSession != null && !existingSession.isExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _completeSignIn(existingSession);
      });
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_isGoogleLoading) return;

    if (!SupabaseConfig.isConfigured || !SupabaseConfig.isInitialized) {
      _showMessage(
        'ยังไม่ได้ตั้งค่า Supabase Publishable key สำหรับแอป',
        isError: true,
      );
      return;
    }

    setState(() => _isGoogleLoading = true);

    try {
      final launched = await SupabaseConfig.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : SupabaseConfig.oauthRedirectUrl,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        queryParams: const {'prompt': 'select_account'},
      );

      if (!launched && mounted) {
        _showMessage('ไม่สามารถเปิดหน้าล็อกอิน Google ได้', isError: true);
      }
    } on AuthException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'เกิดข้อผิดพลาดระหว่างเปิด Google Login กรุณาลองใหม่',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Future<void> _completeSignIn(Session session) async {
    if (!mounted || _signInHandled) return;

    _signInHandled = true;
    AuthSession.saveAccessToken(session.accessToken);

    try {
      if (_signedInWithGoogle(session.user.appMetadata)) {
        await _authRemoteDataSource.syncGoogleProfileImage(
          accessToken: session.accessToken,
        );
      }
    } on AuthApiException catch (error) {
      _signInHandled = false;
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
      return;
    }

    if (!mounted) return;
    _goToHome();
  }

  bool _signedInWithGoogle(Map<String, dynamic> appMetadata) {
    if (appMetadata['provider'] == 'google') return true;

    final providers = appMetadata['providers'];
    return providers is List && providers.contains('google');
  }

  void _handleAuthStateError(Object error, StackTrace stackTrace) {
    if (!mounted) return;

    setState(() => _isGoogleLoading = false);
    _showMessage(
      error is AuthException
          ? error.message
          : 'ไม่สามารถตรวจสอบสถานะการเข้าสู่ระบบได้',
      isError: true,
    );
  }

  void _goToHome() {
    AppRoutes.goToHome(context);
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Colors.red.shade700
              : Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _login() async {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final tokens = await _authRemoteDataSource.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      final authResponse = await SupabaseConfig.client.auth.setSession(
        tokens.refreshToken,
        accessToken: tokens.accessToken,
      );
      final session = authResponse.session;
      if (session == null) {
        throw const AuthApiException('ไม่สามารถบันทึก Session ได้');
      }

      if (!mounted) return;
      _completeSignIn(session);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on AuthException catch (error) {
      if (!mounted) return;
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _authRemoteDataSource.close();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: ResponsivePageBody(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text(
                'ยินดีต้อนรับ',
                style:
                    theme.textTheme.headlineLarge?.copyWith(
                      color: Colors.black,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ) ??
                    const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'มาสนุกกับการยืมกัน !',
                style:
                    theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                      fontSize: 16,
                    ) ??
                    const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              AppTextFormField(
                label: 'อีเมล',
                hintText: 'name@exemple.com',
                prefixIcon: Icons.email_outlined,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกอีเมล';
                  }
                  if (!RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  ).hasMatch(value)) {
                    return 'รูปแบบอีเมลไม่ถูกต้อง';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              AppTextFormField(
                label: 'รหัสผ่าน',
                hintText: 'กรุณากรอกรหัสผ่าน',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                controller: _passwordController,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.fieldIconColor,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกรหัสผ่าน';
                  }
                  if (value.length < 6) {
                    return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    AppRoutes.openForgotPassword(context);
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'ลืมรหัสผ่าน ?',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              AppPrimaryButton(
                text: 'เข้าสู่ระบบ',
                isLoading: _isLoading,
                onPressed: _login,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: AppColors.primaryColor.withValues(alpha: 0.3),
                      thickness: 1,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'หรือ',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: AppColors.primaryColor.withValues(alpha: 0.3),
                      thickness: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SocialButton(
                text: _isGoogleLoading ? 'กำลังเปิด Google...' : 'Google',
                iconPath: 'assets/icons/google.png',
                onPressed: _loginWithGoogle,
              ),
              const SizedBox(height: 48),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'สร้างบัญชีใหม่ ',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () {
                      AppRoutes.openRegister(context);
                    },
                    child: const Text(
                      'สมัครสมาชิก',
                      style: TextStyle(
                        color: AppColors.primaryColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
