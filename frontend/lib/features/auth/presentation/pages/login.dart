import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/app_permission_service.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/auth_divider.dart';
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
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void initState() {
    super.initState();
    // รีเซ็ตสถานะ BLoC เมื่อเปิดหน้านี้ขึ้นมาใหม่
    context.read<AuthBloc>().add(const AuthResetState());

    // ตรวจสอบเซสชันที่มีอยู่แล้วเมื่อเริ่มต้นใช้งานแอป
    if (SupabaseConfig.isInitialized) {
      final existingSession = SupabaseConfig.client.auth.currentSession;
      if (existingSession != null && !existingSession.isExpired) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<AuthBloc>().add(AuthAuthStateChanged(existingSession));
        });
      }
    }

    // แสดง Dialog ขออนุญาตรับการแจ้งเตือนเมื่อเข้าสู่หน้า Login
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppPermissionService.checkAndPromptNotificationPermission(context);
      }
    });
  }

  void _loginWithGoogle() {
    context.read<AuthBloc>().add(const AuthGoogleLoginRequested());
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

  void _login() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
          AuthLoginRequested(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
        );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is LoginLoading) {
          setState(() {
            _isLoading = true;
            _isGoogleLoading = false;
          });
        } else if (state is GoogleLoginLoading) {
          setState(() {
            _isLoading = false;
            _isGoogleLoading = true;
          });
        } else if (state is LoginSuccess || state is GoogleLoginSuccess) {
          setState(() {
            _isLoading = false;
            _isGoogleLoading = false;
          });
          _goToHome();
        } else if (state is LoginFailure) {
          setState(() {
            _isLoading = false;
            _isGoogleLoading = false;
          });
          _showMessage(state.message, isError: true);
        }
      },
      child: Scaffold(
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
                const AuthDivider(),
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
      ),
    );
  }
}
