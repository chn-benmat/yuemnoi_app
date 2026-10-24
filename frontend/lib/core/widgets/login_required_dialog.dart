import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../theme/app_text_styles.dart';
import 'app_primary_button.dart';

enum LoginPromptAction { login, register }

class LoginRequiredDialog extends StatelessWidget {
  const LoginRequiredDialog({
    super.key,
    this.title = defaultTitle,
    this.message = defaultMessage,
  });

  static const defaultTitle = 'เข้าสู่ระบบก่อนใช้งาน';
  static const defaultMessage =
      'เพื่อเช่าอุปกรณ์ พูดคุย\nและติดตามรายการของคุณ';
  final String title;
  final String message;

  static Future<LoginPromptAction?> show(
    BuildContext context, {
    String title = defaultTitle,
    String message = defaultMessage,
  }) {
    return showDialog<LoginPromptAction>(
      context: context,
      barrierColor: const Color(0x800F0720),
      builder: (_) => LoginRequiredDialog(title: title, message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        key: const ValueKey('login-required-dialog-content'),
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1E5FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.primaryColor,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF32134F),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    height: 1.6,
                    color: Color(0xFF756681),
                  ),
                ),
                const SizedBox(height: 20),
                AppPrimaryButton(
                  text: 'เข้าสู่ระบบ',
                  onPressed: () =>
                      Navigator.of(context).pop(LoginPromptAction.login),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'ยังไม่มีบัญชี?',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF756681),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(LoginPromptAction.register),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryColor,
                        textStyle: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('ลงทะเบียน'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'ปิด',
              icon: const Icon(Icons.close_rounded, size: 20),
              color: const Color(0xFF8D8198),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
