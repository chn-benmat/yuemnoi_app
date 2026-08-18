import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/services/app_permission_service.dart';
import '../../../../core/theme/app_text_styles.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  String? _avatarUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser
        : null;
    final meta = user?.userMetadata ?? {};

    _displayNameCtrl = TextEditingController(
      text: (meta['display_name'] ?? meta['full_name'] ?? user?.email?.split('@').first ?? '').toString(),
    );
    _usernameCtrl = TextEditingController(
      text: (meta['username'] ?? user?.email?.split('@').first ?? '').toString(),
    );
    _bioCtrl = TextEditingController(
      text: (meta['bio'] ?? '').toString(),
    );
    _avatarUrl = (meta['avatar_url'] ?? meta['picture'] ?? '').toString();
    if (_avatarUrl!.isEmpty) _avatarUrl = null;
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final hasPermission =
        await AppPermissionService.requestGalleryPermission(context);
    if (!hasPermission || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      // TODO: upload image and update _avatarUrl
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'บันทึกข้อมูลเรียบร้อย',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
        backgroundColor: AppColors.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
          'แก้ไขโปรไฟล์',
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
              // ── Avatar ─────────────────────────────────────────
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.gradient2, AppColors.primaryColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: _avatarUrl != null
                            ? Image.network(_avatarUrl!, fit: BoxFit.cover)
                            : Container(
                                color: const Color(0xFFF3E8FF),
                                child: const Icon(
                                  Icons.person_rounded,
                                  size: 48,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Section: ข้อมูลตัวตน ─────────────────────────
              const _SectionTitle(title: 'ข้อมูลตัวตน'),
              const SizedBox(height: 12),
              _FormField(
                controller: _displayNameCtrl,
                label: 'ชื่อแสดงตัวตน',
                hint: 'กรอกชื่อที่ต้องการแสดง',
                icon: Icons.badge_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
              ),
              const SizedBox(height: 14),
              _FormField(
                controller: _usernameCtrl,
                label: 'ชื่อผู้ใช้',
                hint: 'username',
                icon: Icons.alternate_email_rounded,
              ),
              const SizedBox(height: 14),
              _FormField(
                controller: _bioCtrl,
                label: 'ชีวประวัติ / แนะนำตัว',
                hint: 'เขียนอะไรสักอย่างเกี่ยวกับตัวคุณ...',
                icon: Icons.info_outline_rounded,
                maxLines: 3,
              ),
              const SizedBox(height: 28),

              // ── Save button ──────────────────────────────────
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primaryColor.withValues(alpha: 0.6),
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
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'บันทึกข้อมูล',
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

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.labelColor,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 14,
          color: Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: AppColors.hintTextColor,
          ),
          hintStyle: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: AppColors.hintTextColor,
          ),
          prefixIcon: Icon(icon, color: AppColors.fieldIconColor, size: 20),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.primaryColor, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.red, width: 1.5),
          ),
        ),
      ),
    );
  }
}
