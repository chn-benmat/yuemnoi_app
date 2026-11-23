import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/utils/app_form_validators.dart';
import '../../../../core/widgets/responsive_app_bar_title.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/auth_inline_error.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.accessToken});

  final String accessToken;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // รีเซ็ตสถานะ BLoC เมื่อเข้าหน้านี้
    context.read<AuthBloc>().add(const AuthResetState());
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _errorMessage = null);
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
      AuthChangePasswordRequested(
        accessToken: widget.accessToken,
        newPassword: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is ChangePasswordLoading) {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
        } else if (state is ChangePasswordSuccess) {
          setState(() {
            _isLoading = false;
          });

          // นำทางกลับไปยังหน้า Login (โดยการล้าง Stack ทั้งหมดออกไปจนถึงหน้าแรกสุด หรือหน้าระดับบนสุด)
          AppRoutes.goToLogin(context);
        } else if (state is ChangePasswordFailure) {
          setState(() {
            _isLoading = false;
            _errorMessage = userFriendlyErrorMessage(state.message);
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              AppRoutes.pop(context);
            },
          ),
          title: const ResponsiveAppBarTitle('เปลี่ยนรหัสผ่านใหม่'),
        ),
        body: ResponsivePageBody(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  'ตั้งค่ารหัสผ่านใหม่',
                  style:
                      theme.textTheme.headlineLarge?.copyWith(
                        color: Colors.black,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ) ??
                      const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'กรุณากรอกรหัสผ่านใหม่ที่ต้องการใช้งาน',
                  style:
                      theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.black54,
                        fontSize: 15,
                      ) ??
                      const TextStyle(fontSize: 15, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                AppTextFormField(
                  label: 'รหัสผ่านใหม่',
                  hintText: 'กรุณากรอกรหัสผ่านใหม่',
                  obscureText: _obscurePassword,
                  controller: _passwordController,
                  onChanged: (_) => _clearFormError(),
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
                  validator: AppFormValidators.password(
                    requiredMessage: 'กรุณากรอกรหัสผ่านใหม่',
                  ),
                ),
                const SizedBox(height: 24),
                AppTextFormField(
                  label: 'ยืนยันรหัสผ่านใหม่',
                  hintText: 'กรอกรหัสยืนยันผ่านใหม่',
                  obscureText: _obscureConfirmPassword,
                  controller: _confirmPasswordController,
                  onChanged: (_) => _clearFormError(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.fieldIconColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                  ),
                  validator: AppFormValidators.confirmation(
                    () => _passwordController.text,
                    requiredMessage: 'กรุณากรอกยืนยันรหัสผ่านใหม่',
                  ),
                ),
                const SizedBox(height: 48),
                AuthInlineError(message: _errorMessage),
                AppPrimaryButton(
                  text: 'เปลี่ยนรหัสผ่าน',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearFormError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }
}
