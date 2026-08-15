import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';

class ChangeAccountScreen extends StatelessWidget {
  const ChangeAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ความปลอดภัย',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SecurityItem(
                icon: Icons.badge_outlined,
                title: 'นิกเนม',
                subtitle: 'เปลี่ยนชื่อแสดงตัวตน',
                onTap: () => AppRoutes.openEditProfile(context),
              ),
              Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
              _SecurityItem(
                icon: Icons.email_outlined,
                title: 'อีเมล',
                subtitle: 'เปลี่ยนอีเมลที่เชื่อมต่อ',
                onTap: () => AppRoutes.openEditContact(context),
              ),
              Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
              _SecurityItem(
                icon: Icons.lock_outline_rounded,
                title: 'เปลี่ยนรหัสผ่าน',
                subtitle: 'อัพเดตรหัสผ่านของคุณ',
                showDivider: false,
                onTap: () => AppRoutes.openProfileChangePassword(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Security Item ────────────────────────────────────────────────────────────

class _SecurityItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool showDivider;
  final VoidCallback? onTap;

  const _SecurityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showDivider = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primaryColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: AppColors.hintTextColor,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.hintTextColor),
          ],
        ),
      ),
    );
  }
}
