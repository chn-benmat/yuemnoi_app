import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/utils/app_form_validators.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/auth_divider.dart';
import '../widgets/auth_inline_error.dart';
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
  bool _restoreDialogOpen = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<AuthBloc>();
    // รีเซ็ตสถานะ BLoC เมื่อเปิดหน้านี้ขึ้นมาใหม่
    bloc.add(const AuthResetState());

    // การตรวจเซสชัน OAuth ทำใน BLoC แม้ callback จะมาถึงก่อนเปิดหน้านี้
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = bloc.state;
      if (state is LoginNeedsAccountRestore) {
        _offerAccountRestore(state);
      } else if (AuthSession.isAuthenticated) {
        _handleSuccess();
      }
    });
  }

  void _loginWithGoogle() {
    context.read<AuthBloc>().add(const AuthGoogleLoginRequested());
  }

  void _goToHome() {
    AppRoutes.goToHome(context);
  }

  void _handleSuccess() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    } else {
      _goToHome();
    }
  }

  Future<void> _offerAccountRestore(LoginNeedsAccountRestore state) async {
    if (_restoreDialogOpen) return;
    final bloc = context.read<AuthBloc>();
    _restoreDialogOpen = true;
    setState(() {
      _isLoading = false;
      _isGoogleLoading = false;
      _errorMessage = null;
    });
    final deadline = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(state.deleteAfter.toLocal());
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('กู้คืนบัญชี'),
        content: Text(
          'บัญชีนี้มีกำหนดลบถาวรวันที่ $deadline '
          'ยืนยันเพื่อยกเลิกการลบและกลับมาใช้งานบัญชี',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    _restoreDialogOpen = false;
    if (!bloc.isClosed) {
      bloc.add(AuthAccountRestoreDecided(confirmed: confirmed == true));
    }
  }

  void _clearFormError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  void _login() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _errorMessage = null);
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
        if (state is AuthInitial) {
          setState(() {
            _isLoading = false;
            _isGoogleLoading = false;
            _errorMessage = null;
          });
        } else if (state is LoginLoading) {
          setState(() {
            _isLoading = true;
            _isGoogleLoading = false;
            _errorMessage = null;
          });
        } else if (state is GoogleLoginLoading) {
          setState(() {
            _isLoading = false;
            _isGoogleLoading = true;
            _errorMessage = null;
          });
        } else if (state is LoginNeedsAccountRestore) {
          _offerAccountRestore(state);
        } else if (state is LoginSuccess || state is GoogleLoginSuccess) {
          setState(() {
            _isLoading = false;
            _isGoogleLoading = false;
          });
          _handleSuccess();
        } else if (state is LoginFailure) {
          setState(() {
            _isLoading = false;
            _isGoogleLoading = false;
            _errorMessage = userFriendlyErrorMessage(state.message);
          });
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: Navigator.of(context).canPop()
              ? AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.dark,
                  leading: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.black87,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    tooltip: 'ย้อนกลับ',
                  ),
                )
              : null,
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
                    onChanged: (_) => _clearFormError(),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: AppFormValidators.email(),
                  ),
                  const SizedBox(height: 24),
                  AppTextFormField(
                    label: 'รหัสผ่าน',
                    hintText: 'กรุณากรอกรหัสผ่าน',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    controller: _passwordController,
                    onChanged: (_) => _clearFormError(),
                    textInputAction: TextInputAction.done,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.fieldIconColor,
                      ),
                      tooltip: _obscurePassword
                          ? 'แสดงรหัสผ่าน'
                          : 'ซ่อนรหัสผ่าน',
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    validator: AppFormValidators.password(),
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
                  const SizedBox(height: 12),
                  AuthInlineError(message: _errorMessage),
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
      ),
    );
  }
}
