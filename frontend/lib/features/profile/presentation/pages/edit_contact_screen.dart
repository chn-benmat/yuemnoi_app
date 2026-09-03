import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_text_styles.dart';

class EditContactScreen extends StatefulWidget {
  const EditContactScreen({super.key});

  @override
  State<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends State<EditContactScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser
        : null;

    _emailCtrl = TextEditingController(text: user?.email ?? '');
    _phoneCtrl = TextEditingController(
      text: (user?.userMetadata?['phone'] ?? user?.phone ?? '').toString(),
    );

    _loadContactFromBackend();
  }

  Future<void> _loadContactFromBackend() async {
    try {
      final session = SupabaseConfig.isInitialized
          ? SupabaseConfig.client.auth.currentSession
          : null;
      if (session == null) return;

      final apiClient = DioApiClient();
      final response = await apiClient.get(
        '/api/v1/user/profile',
        headers: {'Authorization': 'Bearer '},
      );

      if (response.statusCode == 200 && response.data is Map && mounted) {
        final data = response.data as Map;
        if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
          setState(() {
            _phoneCtrl.text = data['phone'].toString();
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    setState(() => _isSaving = true);

    try {
      final session = SupabaseConfig.isInitialized
          ? SupabaseConfig.client.auth.currentSession
          : null;
      final accessToken = session?.accessToken;
      if (accessToken == null) {
        throw Exception('กรุณาเข้าสู่ระบบก่อน');
      }

      final apiClient = DioApiClient();
      final response = await apiClient.put(
        '/api/v1/user/contact',
        headers: {'Authorization': 'Bearer '},
        data: {'phone': phone},
      );

      if (response.statusCode != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : null;
        throw Exception(errorMsg ?? 'ไม่สามารถบันทึกเบอร์โทรศัพท์ได้');
      }

      _phoneCtrl.text = phone;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'บันทึกข้อมูลติดต่อเรียบร้อย',
            style: TextStyle(fontFamily: AppTextStyles.fontFamily),
          ),
          backgroundColor: AppColors.primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
          'ข้อมูลติดต่อ',
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
              // ── Email ────────────────────────────────────────
              _ContactField(
                controller: _emailCtrl,
                label: 'อีเมลที่อยู่',
                hint: 'กรอกอีเมลของคุณ',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'กรุณากรอกอีเมล';
                  if (!v.contains('@')) return 'รูปแบบอีเมลไม่ถูกต้อง';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── Phone ────────────────────────────────────────
              _ContactField(
                controller: _phoneCtrl,
                label: 'หมายเลขโทรศัพท์ที่เชื่อมต่อกัน',
                hint: '0xx-xxx-xxxx',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  final phone = value?.replaceAll(RegExp(r'\D'), '') ?? '';
                  if (phone.isEmpty) return 'กรุณากรอกเบอร์โทรศัพท์';
                  if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
                    return 'เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วย 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // ── Save ─────────────────────────────────────────
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primaryColor.withValues(alpha: 0.6),
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

// ─── Contact Field ────────────────────────────────────────────────────────────

class _ContactField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _ContactField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
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
        keyboardType: keyboardType,
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
