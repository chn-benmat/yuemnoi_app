import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

// คำอธิบาย: วิดเจ็ตสำหรับแสดงการนับเวลาถอยหลังเพื่อส่งรหัส OTP หรือปุ่มกดส่งรหัสอีกครั้งเมื่อเวลาหมด
class OtpResendSection extends StatelessWidget {
  final bool canResend;
  final bool isResending;
  final int secondsRemaining;
  final VoidCallback onResend;

  const OtpResendSection({
    super.key,
    required this.canResend,
    required this.isResending,
    required this.secondsRemaining,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: canResend
          ? TextButton(
              onPressed: isResending ? null : onResend,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: isResending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'ส่งรหัสอีกครั้ง',
                      style: TextStyle(
                        color: AppColors.primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            )
          : Text(
              'ส่งรหัส OTP ใหม่ในอีก ${secondsRemaining}s',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }
}
