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

class ForgetPasswordScreen extends StatefulWidget {
  const ForgetPasswordScreen({super.key});

  @override
  State<ForgetPasswordScreen> createState() => _ForgetPasswordScreenState();
}

class _ForgetPasswordScreenState extends State<ForgetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // รีเซ็ตสถานะ BLoC เมื่อเข้าหน้านี้
    context.read<AuthBloc>().add(const AuthResetState());
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
      AuthSendOtpRequested(email: _emailController.text.trim()),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is SendOtpLoading) {
          setState(() {
            _isLoading = true;
          });
        } else if (state is SendOtpSuccess) {
          setState(() {
            _isLoading = false;
          });
          AppRoutes.openOtpVerification(
            context,
            email: _emailController.text.trim(),
          );
        } else if (state is SendOtpFailure) {
          setState(() {
            _isLoading = false;
          });
          _showMessage(state.message, isError: true);
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
          title: const ResponsiveAppBarTitle('ลืมรหัสผ่าน'),
        ),
        body: ResponsivePageBody(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                Center(
                  child: Container(
                    height: 132,
                    width: 132,
                    decoration: const BoxDecoration(color: Colors.transparent),
                    child: Image.asset(
                      'assets/images/overlay.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Text(
                  'กู้คืนรหัสผ่าน',
                  style:
                      theme.textTheme.headlineLarge?.copyWith(
                        color: Colors.black,
                        fontSize: 40,
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
                  'กรุณากรอกอีเมลเพื่อรับรหัส OTP สำหรับตั้งค่ารหัสผ่านใหม่',
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
                  label: 'อีเมล',
                  hintText: 'กรุณากรอกอีเมล',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: AppFormValidators.required('กรุณากรอกอีเมล'),
                ),
                const SizedBox(height: 48),
                AppPrimaryButton(
                  text: 'ส่งรหัส OTP',
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
}
