import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
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

  bool _showCurrentPw = false;
  bool _showNewPw = false;
  bool _showConfirmPw = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'เปลี่ยนรหัสผ่านเรียบร้อย',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
        backgroundColor: AppColors.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
                validator: (v) {
                  if (v == null || v.isEmpty) return 'กรุณากรอกรหัสผ่านเดิม';
                  if (v.length < 6) return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัว';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── New password ──────────────────────────────
              ChangePasswordField(
                controller: _newPwCtrl,
                label: 'รหัสผ่านใหม่',
                hint: 'กรอกรหัสผ่านใหม่',
                showPassword: _showNewPw,
                onToggle: () => setState(() => _showNewPw = !_showNewPw),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'กรุณากรอกรหัสผ่านใหม่';
                  if (v.length < 6) return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัว';
                  return null;
                },
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
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'กรุณายืนยันรหัสผ่านใหม่';
                  }
                  if (v != _newPwCtrl.text) {
                    return 'รหัสผ่านไม่ตรงกัน';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // ── Submit button ─────────────────────────────
              ElevatedButton(
                onPressed: _isSaving ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primaryColor.withValues(
                    alpha: 0.6,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: _isSaving
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
  }
}
