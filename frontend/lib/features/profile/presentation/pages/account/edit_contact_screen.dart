import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/app_form_validators.dart';
import '../../../../../core/utils/phone_formatter.dart';
import '../../bloc/profile_cubit.dart';
import '../../bloc/profile_state.dart';
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
  late final ProfileCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ProfileCubit();

    final user = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser
        : null;

    _emailCtrl = TextEditingController(text: user?.email ?? '');
    // เบอร์ตั้งต้นมาจากโปรไฟล์เมื่อโหลดเสร็จ (profile_tb.phone)
    _phoneCtrl = TextEditingController();

    final session = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentSession
        : null;
    final userId = user?.id ?? '';
    if (userId.isNotEmpty) {
      _cubit.loadProfile(userId: userId, accessToken: session?.accessToken);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final rawInput = _phoneCtrl.text;
    final phoneForSupabase = PhoneFormatter.formatForSupabase(rawInput);

    final session = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentSession
        : null;
    final accessToken = session?.accessToken;
    if (accessToken == null) {
      showAppPopup(context, content: Text('กรุณาเข้าสู่ระบบก่อน'));
      return;
    }

    final success = await _cubit.updatePhone(
      accessToken: accessToken,
      phone: phoneForSupabase,
    );

    if (success && mounted && ModalRoute.of(context)?.isCurrent == true) {
      AppRoutes.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<ProfileCubit, ProfileState>(
        listener: (context, state) {
          if (state is ProfileLoaded) {
            if (_phoneCtrl.text.isEmpty && state.profile.phone.isNotEmpty) {
              _phoneCtrl.text = PhoneFormatter.formatForDisplay(
                state.profile.phone,
              );
            }
            if (_emailCtrl.text.isEmpty && state.profile.email.isNotEmpty) {
              _emailCtrl.text = state.profile.email;
            }
          } else if (state is ProfileActionFailure) {
            showAppPopup(
              context,
              content: Text(
                state.message.replaceAll('Exception: ', ''),
                style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
              ),
            );
          }
        },
        builder: (context, state) {
          final isSaving = state is ProfileActionInProgress;

          return Scaffold(
            backgroundColor: const Color(0xFFFAF9FD),
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text(
                'ข้อมูลติดต่อ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              centerTitle: false,
              elevation: 0,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Email (Read-only) ──────────────────────────
                    EditContactField(
                      controller: _emailCtrl,
                      label: 'อีเมลบัญชี',
                      readOnly: true,
                      hint: 'example@email.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: null,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'อีเมลนี้ใช้เข้าสู่ระบบ ยังไม่สามารถเปลี่ยนในหน้านี้ได้',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF665D73),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Phone ──────────────────────────────────────
                    EditContactField(
                      controller: _phoneCtrl,
                      label: 'เบอร์โทรศัพท์',
                      hint: '0812345678',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(
                          10,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        ),
                      ],
                      validator: AppFormValidators.thaiPhone(),
                    ),
                    const SizedBox(height: 28),

                    // ── Save button ────────────────────────────────
                    ElevatedButton(
                      onPressed: isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primaryColor
                            .withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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
                              'บันทึกข้อมูลติดต่อ',
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
