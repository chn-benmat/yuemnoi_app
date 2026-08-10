import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

// คำอธิบาย: วิดเจ็ตแสดงเส้นแบ่งคั่นคำว่า "หรือ" เพื่อใช้ในหน้าระบบลงชื่อเข้าใช้หรือสมัครสมาชิก
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: AppColors.primaryColor.withValues(alpha: 0.3),
            thickness: 1,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'หรือ',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: AppColors.primaryColor.withValues(alpha: 0.3),
            thickness: 1,
          ),
        ),
      ],
    );
  }
}
