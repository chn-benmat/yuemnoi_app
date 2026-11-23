import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/app_permission_service.dart';
import '../../../../core/utils/app_image_compressor.dart';
import '../../../../core/utils/app_form_validators.dart';
import '../../../../core/widgets/responsive_app_bar_title.dart';
import '../../../../core/widgets/responsive_page_body.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_form_field.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/register_profile_image_picker.dart';
import '../widgets/auth_inline_error.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  Uint8List? _profileImageBytes;
  String? _profileImageFileName;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // รีเซ็ตสถานะ BLoC เมื่อเข้าหน้านี้
    context.read<AuthBloc>().add(const AuthResetState());
  }

  Future<void> _pickProfileImage() async {
    if (_isLoading) return;

    final hasPermission = await AppPermissionService.requestGalleryPermission(
      context,
    );
    if (!hasPermission || !mounted) return;

    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        maxHeight: 1440,
      );
      if (image == null) return;

      final compressed = await AppImageCompressor.compress(
        bytes: await image.readAsBytes(),
        fileName: image.name,
      );
      if (compressed.bytes.length > 5 * 1024 * 1024) {
        if (!mounted) return;
        _showError('รูปโปรไฟล์ต้องมีขนาดไม่เกิน 5 MB');
        return;
      }

      if (!mounted) return;
      setState(() {
        _profileImageBytes = compressed.bytes;
        _profileImageFileName = compressed.fileName;
      });
    } catch (_) {
      if (!mounted) return;
      _showError('ไม่สามารถเลือกรูปโปรไฟล์ได้');
    }
  }

  void _register() {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _errorMessage = null);
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
      AuthRegisterRequested(
        displayName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
        imageBytes: _profileImageBytes,
        imageFileName: _profileImageFileName,
      ),
    );
  }

  void _showError(String message) {
    showAppPopup(context, content: Text(message));
  }

  void _clearFormError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is RegisterLoading) {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
        } else if (state is RegisterSuccess) {
          setState(() {
            _isLoading = false;
          });

          AppRoutes.pop(context, true);
        } else if (state is RegisterFailure) {
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
          title: const ResponsiveAppBarTitle('สมัครสมาชิก'),
        ),
        body: ResponsivePageBody(
          verticalPadding: 24,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // Optional profile photo picker
                RegisterProfileImagePicker(
                  profileImageBytes: _profileImageBytes,
                  onTap: _pickProfileImage,
                ),
                const SizedBox(height: 24),
                // Name Field
                AppTextFormField(
                  label: 'ชื่อ - นามสกุล',
                  hintText: 'กรุณากรอกชื่อ - นามสกุล',
                  controller: _nameController,
                  onChanged: (_) => _clearFormError(),
                  validator: AppFormValidators.required(
                    'กรุณากรอกชื่อ - นามสกุล',
                  ),
                ),
                const SizedBox(height: 16),
                // Email Field
                AppTextFormField(
                  label: 'อีเมล',
                  hintText: 'name@exemple.com',
                  controller: _emailController,
                  onChanged: (_) => _clearFormError(),
                  keyboardType: TextInputType.emailAddress,
                  validator: AppFormValidators.email(),
                ),
                const SizedBox(height: 16),
                // Phone Field
                AppTextFormField(
                  label: 'เบอร์โทรศัพท์',
                  hintText: '0812345678',
                  controller: _phoneController,
                  onChanged: (_) => _clearFormError(),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: AppFormValidators.thaiPhone(localInputOnly: true),
                ),
                const SizedBox(height: 16),
                // Password Field
                AppTextFormField(
                  label: 'รหัสผ่าน',
                  hintText: 'กรุณากรอกรหัสผ่าน',
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
                  validator: AppFormValidators.password(),
                ),
                const SizedBox(height: 16),
                // Confirm Password Field
                AppTextFormField(
                  label: 'ยืนยันรหัสผ่าน',
                  hintText: 'กรุณากรอกรหัสยืนยันผ่าน',
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
                  ),
                ),
                const SizedBox(height: 32),
                AuthInlineError(message: _errorMessage),
                // Register Button
                AppPrimaryButton(
                  text: 'สร้างบัญชี',
                  isLoading: _isLoading,
                  onPressed: _register,
                ),
                const SizedBox(height: 24),
                // Footer text
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'มีบัญชีแล้ว? ',
                      style: TextStyle(color: Colors.black54, fontSize: 15),
                    ),
                    GestureDetector(
                      onTap: () {
                        AppRoutes.pop(context);
                      },
                      child: const Text(
                        'เข้าสู่ระบบ',
                        style: TextStyle(
                          color: AppColors.primaryColor,
                          fontSize: 15,
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
