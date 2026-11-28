import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_popup.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_event.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import '../../widgets/account/change_account_widgets.dart';

class ChangeAccountScreen extends StatelessWidget {
  const ChangeAccountScreen({super.key});

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final bloc = context.read<AuthBloc>();
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BlocConsumer<AuthBloc, AuthState>(
        bloc: bloc,
        buildWhen: (_, state) =>
            state is AccountDeletionLoading || state is AccountDeletionFailure,
        listenWhen: (_, state) => state is AccountDeletionScheduled,
        listener: (_, _) => Navigator.of(ctx).pop(true),
        builder: (context, state) {
          final isSubmitting = state is AccountDeletionLoading;
          return PopScope(
            canPop: !isSubmitting,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'ลบบัญชีผู้ใช้',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'บัญชีจะถูกลบถาวรหลัง 30 วัน คุณสามารถเข้าสู่ระบบเพื่อกู้คืนบัญชีได้ภายในกำหนดนี้',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (state is AccountDeletionFailure) ...[
                    const SizedBox(height: 12),
                    Text(
                      userFriendlyErrorMessage(state.message),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    'ยกเลิก',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () => bloc.add(const AuthAccountDeletionRequested()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isSubmitting ? 'กำลังส่งคำขอ...' : 'ยืนยันลบบัญชี',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (deleted != true || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ตั้งเวลาลบบัญชีแล้ว')));
    AppRoutes.goToLogin(context);
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ศูนย์ความเป็นส่วนตัว',
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('บัญชีและความปลอดภัย'),
            _buildCardGroup([
              AccountSecurityItem(
                icon: Icons.lock_outline_rounded,
                iconBgColor: const Color(0xFFF3E8FF),
                iconColor: AppColors.primaryColor,
                title: 'เปลี่ยนรหัสผ่าน',
                subtitle: 'อัปเดตรหัสผ่านของคุณเพื่อความปลอดภัย',
                onTap: () => AppRoutes.openProfileChangePassword(context),
              ),
            ]),

            const SizedBox(height: 20),
            _buildSectionHeader('การจัดการบัญชี'),
            _buildCardGroup([
              AccountSecurityItem(
                icon: Icons.delete_outline_rounded,
                iconBgColor: const Color(0xFFFEE2E2),
                iconColor: Colors.red.shade700,
                title: 'ลบบัญชีผู้ใช้',
                subtitle: 'ซ่อนโปรไฟล์และตั้งเวลาลบบัญชีถาวร',
                isDanger: true,
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildCardGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 64,
      endIndent: 16,
      color: Colors.grey.shade100,
    );
  }
}
