import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/app_form_validators.dart';
import '../../bloc/profile_cubit.dart';
import '../../bloc/profile_state.dart';
import '../../widgets/account/change_password_widgets.dart';

class ProfileChangePasswordScreen extends StatefulWidget {
  const ProfileChangePasswordScreen({super.key});

  @override
  State<ProfileChangePasswordScreen> createState() =>
      _ProfileChangePasswordScreenState();
}

class _ProfileChangePasswordScreenState
    extends State<ProfileChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  late final ProfileCubit _cubit;

  bool _showCurrentPw = false;
  bool _showNewPw = false;
  bool _showConfirmPw = false;

  @override
  void initState() {
    super.initState();
    _cubit = ProfileCubit();
  }

  @override
  void dispose() {
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final session = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentSession
        : null;
    final accessToken = session?.accessToken;
    if (accessToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('กรุณาเข้าสู่ระบบก่อนเปลี่ยนรหัสผ่าน'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    await _cubit.changeUserPassword(
      accessToken: accessToken,
      newPassword: _newPwCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
          if (state is ProfileActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.message,
                  style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
                ),
                backgroundColor: AppColors.primaryColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
            Navigator.of(context).pop();
          } else if (state is ProfileActionFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.message.replaceAll('Exception: ', ''),
                  style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          final isSaving = state is ProfileActionInProgress;

          return Scaffold(
            backgroundColor: const Color(0xFFF7F7F9),
            appBar: AppBar(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              leading: const BackButton(),
              title: const Text(
                'เปลี่ยนรหัสผ่าน',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              centerTitle: true,
              elevation: 0,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Current password ──────────────────────────
                    ChangePasswordField(
                      controller: _currentPwCtrl,
                      label: 'รหัสผ่านเดิม',
                      hint: 'กรอกรหัสผ่านปัจจุบัน',
                      showPassword: _showCurrentPw,
                      onToggle: () =>
                          setState(() => _showCurrentPw = !_showCurrentPw),
                      validator: AppFormValidators.password(
                        requiredMessage: 'กรุณากรอกรหัสผ่านเดิม',
                        lengthMessage: 'รหัสผ่านต้องมีอย่างน้อย 6 ตัว',
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── New password ──────────────────────────────
                    ChangePasswordField(
                      controller: _newPwCtrl,
                      label: 'รหัสผ่านใหม่',
                      hint: 'กรอกรหัสผ่านใหม่',
                      showPassword: _showNewPw,
                      onToggle: () => setState(() => _showNewPw = !_showNewPw),
                      validator: AppFormValidators.password(
                        requiredMessage: 'กรุณากรอกรหัสผ่านใหม่',
                        lengthMessage: 'รหัสผ่านต้องมีอย่างน้อย 6 ตัว',
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Confirm password ──────────────────────────
                    ChangePasswordField(
                      controller: _confirmPwCtrl,
                      label: 'ยืนยันรหัสผ่านใหม่',
                      hint: 'กรอกรหัสผ่านใหม่อีกครั้ง',
                      showPassword: _showConfirmPw,
                      onToggle: () =>
                          setState(() => _showConfirmPw = !_showConfirmPw),
                      validator: AppFormValidators.confirmation(
                        () => _newPwCtrl.text,
                        requiredMessage: 'กรุณายืนยันรหัสผ่านใหม่',
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Submit button ─────────────────────────────
                    ElevatedButton(
                      onPressed: isSaving ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primaryColor
                            .withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        minimumSize: const Size(double.infinity, 52),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'เปลี่ยนรหัสผ่าน',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
