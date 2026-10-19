import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../navigation/app_routes.dart';
import '../network/auth_session.dart';
import '../theme/app_text_styles.dart';

abstract final class AuthGuard {
  static bool get isAuthenticated => AuthSession.isAuthenticated;

  /// ตรวจสอบการยืนยันตัวตน หากยังไม่ล็อกอินจะแสดงกล่องข้อความชวนล็อกอิน
  /// คืนค่า `true` หากล็อกอินสำเร็จหรือล็อกอินอยู่แล้ว, และ `false` หากผู้ใช้ยกเลิก
  static Future<bool> requireAuth(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'เข้าสู่ระบบ / สมัครสมาชิก',
    String cancelLabel = 'ไว้ทีหลัง',
  }) async {
    if (isAuthenticated) {
      return true;
    }

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 14,
            color: Color(0xFF6B7280),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldLogin != true || !context.mounted) {
      return false;
    }

    final loginResult = await AppRoutes.pushLogin(context);
    return loginResult == true || isAuthenticated;
  }
}
