import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
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

    final rawPhone = (user?.userMetadata?['phone'] ?? user?.phone ?? '')
        .toString();

    _emailCtrl = TextEditingController(text: user?.email ?? '');
    _phoneCtrl = TextEditingController(
      text: PhoneFormatter.formatForDisplay(rawPhone),
    );

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
    final phoneForDisplay = PhoneFormatter.formatForDisplay(rawInput);

    final session = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentSession
        : null;
    final accessToken = session?.accessToken;
    if (accessToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('กรุณาเข้าสู่ระบบก่อน'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    final success = await _cubit.updatePhone(
      accessToken: accessToken,
      phone: phoneForSupabase,
    );

    if (success && mounted) {
      _phoneCtrl.text = phoneForDisplay;
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
          } else if (state is ProfileActionSuccess) {
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
                    // ── Email (Read-only) ──────────────────────────
                    EditContactField(
                      controller: _emailCtrl,
                      label: 'อีเมล',
                      hint: 'example@email.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: null,
                    ),
                    const SizedBox(height: 20),

                    // ── Phone ──────────────────────────────────────
                    EditContactField(
                      controller: _phoneCtrl,
                      label: 'เบอร์โทรศัพท์',
                      hint: '08X-XXX-XXXX',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
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
