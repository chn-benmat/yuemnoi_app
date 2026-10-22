import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../network/auth_session.dart';
import '../widgets/login_required_dialog.dart';

abstract final class AuthGuard {
  static bool get isAuthenticated => AuthSession.isAuthenticated;

  /// ตรวจสอบการยืนยันตัวตน หากยังไม่ล็อกอินจะแสดงกล่องข้อความชวนล็อกอิน
  /// คืนค่า `true` หากล็อกอินสำเร็จหรือล็อกอินอยู่แล้ว, และ `false` หากผู้ใช้ยกเลิก
  static Future<bool> requireAuth(
    BuildContext context, {
    String title = LoginRequiredDialog.defaultTitle,
    String message = LoginRequiredDialog.defaultMessage,
  }) async {
    if (isAuthenticated) return true;

    final action = await LoginRequiredDialog.show(
      context,
      title: title,
      message: message,
    );
    if (action == null || !context.mounted) return false;

    if (action == LoginPromptAction.register) {
      await AppRoutes.openRegister(context);
      return isAuthenticated;
    }

    final loginResult = await AppRoutes.pushLogin(context);
    return loginResult == true || isAuthenticated;
  }
}
