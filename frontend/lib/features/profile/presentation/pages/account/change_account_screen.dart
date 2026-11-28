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
      barrierColor: const Color(0x990E0720),
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
            child: _DeleteAccountDialog(
              isSubmitting: isSubmitting,
              errorMessage: state is AccountDeletionFailure
                  ? userFriendlyErrorMessage(state.message)
                  : null,
              onCancel: () => Navigator.pop(ctx),
              onConfirm: () => bloc.add(const AuthAccountDeletionRequested()),
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
}

class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog({
    required this.isSubmitting,
    required this.errorMessage,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(
      color: Color(0xFF554A65),
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 14,
      height: 1.5,
    );
    const actionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );
    const actionTextStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );
    const actionPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 12);
    const dangerColor = Color(0xFFB42338);
    const loadingColor = Color(0xFF862740);

    return AlertDialog(
      scrollable: true,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 388),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      title: Text(
        'ลบบัญชีผู้ใช้',
        textAlign: TextAlign.center,
        style: AppTextStyles.headingLarge.copyWith(
          color: const Color(0xFF241936),
          fontSize: 22,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFFEBD9FC), Color(0xFFF7F0FF)],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Image(
                  image: AssetImage('assets/images/yuemnoi_crying.png'),
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'โปรไฟล์และประกาศจะถูกซ่อนทันที\n'
            'บัญชีจะถูกลบถาวรเมื่อครบ 30 วัน',
            textAlign: TextAlign.center,
            style: bodyStyle,
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFFF7F1FE),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFEADBF9),
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(
                        Icons.history_rounded,
                        size: 20,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'กู้คืนได้ภายใน 30 วัน',
                          style: bodyStyle.copyWith(
                            color: const Color(0xFF4F266B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'เข้าสู่ระบบอีกครั้ง แล้วกดยืนยันการกู้คืน',
                          style: bodyStyle.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (errorMessage case final String message) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: bodyStyle.copyWith(color: dangerColor),
              ),
            ),
          ],
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: isSubmitting ? null : onCancel,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF1ECF6),
                  foregroundColor: const Color(0xFF4F266B),
                  minimumSize: const Size(0, 50),
                  padding: actionPadding,
                  textStyle: actionTextStyle,
                  shape: actionShape,
                ),
                child: const Text('ยกเลิก', textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: isSubmitting ? null : onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: dangerColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFF9E4E8),
                  disabledForegroundColor: loadingColor,
                  minimumSize: const Size(0, 50),
                  padding: actionPadding,
                  textStyle: actionTextStyle,
                  shape: actionShape,
                ),
                icon: isSubmitting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          color: loadingColor,
                          strokeWidth: 2,
                        ),
                      )
                    : null,
                label: Text(
                  isSubmitting ? 'กำลังส่งคำขอ…' : 'ลบบัญชี',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
