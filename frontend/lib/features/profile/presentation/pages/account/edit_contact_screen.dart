import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/phone_formatter.dart';
import '../../widgets/account/edit_contact_widgets.dart';

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

    final rawPhone = (user?.userMetadata?['phone'] ?? user?.phone ?? '')
        .toString();

    _emailCtrl = TextEditingController(text: user?.email ?? '');
    _phoneCtrl = TextEditingController(
      text: PhoneFormatter.formatForDisplay(rawPhone),
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
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (response.statusCode == 200 && response.data is Map && mounted) {
        final data = response.data as Map;
        if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
          setState(() {
            _phoneCtrl.text = PhoneFormatter.formatForDisplay(
              data['phone'].toString(),
            );
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

    final rawInput = _phoneCtrl.text;
    final phoneForSupabase = PhoneFormatter.formatForSupabase(rawInput);
    final phoneForDisplay = PhoneFormatter.formatForDisplay(rawInput);
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
        headers: {'Authorization': 'Bearer $accessToken'},
        data: {'phone': phoneForSupabase},
      );

      if (response.statusCode != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']?.toString()
            : null;
        throw Exception(errorMsg ?? 'ไม่สามารถบันทึกเบอร์โทรศัพท์ได้');
      }

      // บันทึกลงใน Supabase User Metadata ให้เป็น +66 โดยตรงด้วย
      try {
        await SupabaseConfig.client.auth.updateUser(
          UserAttributes(data: {'phone': phoneForSupabase}),
        );
      } catch (_) {}

      // อัปเดตช่องข้อความในหน้าจอให้แสดงเป็นเลข 0 แทน +66
      _phoneCtrl.text = phoneForDisplay;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'บันทึกข้อมูลติดต่อเรียบร้อย',
            style: TextStyle(fontFamily: AppTextStyles.fontFamily),
          ),
          backgroundColor: AppColors.primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
              EditContactField(
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
              EditContactField(
                controller: _phoneCtrl,
                label: 'หมายเลขโทรศัพท์ที่เชื่อมต่อกัน',
                hint: '0xx-xxx-xxxx',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  final phone = value?.trim() ?? '';
                  if (phone.isEmpty) return 'กรุณากรอกเบอร์โทรศัพท์';
                  if (!PhoneFormatter.isValidPhone(phone)) {
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
