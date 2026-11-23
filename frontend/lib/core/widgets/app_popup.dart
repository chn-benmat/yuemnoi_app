import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../theme/app_text_styles.dart';

String userFriendlyErrorMessage(String raw) {
  raw = raw.trim();
  if (raw.isEmpty) return 'ไม่สามารถดำเนินการได้ในขณะนี้ กรุณาลองใหม่';

  final containsTechnicalDetails = RegExp(
    r'(exception|stack.?trace|#\d+\s|\.dart:\d+|\.go:\d+|pgrst|postgres|postgrest|dioexception|socketexception|stateerror|bad state:|sqlstate|error_code|statuscode|internal server error|typeerror|nosuchmethod|assertionerror|rangeerror|argumenterror|unhandled|^error\b|\b[45]\d\d\b)',
    caseSensitive: false,
  ).hasMatch(raw);
  if (!containsTechnicalDetails) return raw;

  if (RegExp(
    r'(timeout|timed out|deadline exceeded)',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่';
  }
  if (RegExp(
    r'(socketexception|failed host lookup|connection error|network|internet|no address associated)',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return 'เชื่อมต่ออินเทอร์เน็ตไม่ได้ กรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่';
  }
  if (RegExp(
    r'(401|unauthorized|invalid login|expired token|session expired)',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return 'เซสชันหมดอายุหรือข้อมูลเข้าสู่ระบบไม่ถูกต้อง กรุณาเข้าสู่ระบบอีกครั้ง';
  }
  if (RegExp(
    r'(403|forbidden|permission denied|42501|row-level security)',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return 'บัญชีนี้ไม่มีสิทธิ์ดำเนินการ กรุณาตรวจสอบบัญชีที่ใช้อยู่';
  }
  if (RegExp(
    r'(404|not found|does not exist)',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return 'ไม่พบข้อมูลที่ต้องการ อาจถูกลบหรือเปลี่ยนแปลงไปแล้ว';
  }
  if (RegExp(
    r'(23505|duplicate|already exists|already registered)',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return 'ข้อมูลนี้มีอยู่แล้ว กรุณาตรวจสอบข้อมูลที่กรอก';
  }
  if (RegExp(
    r'(400|invalid input|validation|malformed|invalid argument)',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return 'ข้อมูลไม่ถูกต้องหรือไม่ครบถ้วน กรุณาตรวจสอบแล้วลองใหม่';
  }
  return 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง';
}

String _userFriendlyError(Widget content) {
  if (content is! Text) {
    return 'ไม่สามารถดำเนินการได้ในขณะนี้ กรุณาลองใหม่';
  }

  return userFriendlyErrorMessage(
    content.data ?? content.textSpan?.toPlainText() ?? '',
  );
}

/// แสดงข้อความที่เข้าใจง่าย และแปลงรายละเอียดเชิงเทคนิคเป็นคำอธิบายสำหรับผู้ใช้
void showAppPopup(BuildContext context, {required Widget content}) {
  final message = _userFriendlyError(content);
  final navigator = Navigator.of(context, rootNavigator: true);
  // รอให้การปิดหน้าหรือเปลี่ยนหน้าของผู้เรียกเสร็จก่อนเปิด popup
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) return;
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/crying.png',
                width: 132,
                height: 132,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text(
                'มีข้อผิดพลาดเกิดขึ้น',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E2022),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'ยืนยัน',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}
