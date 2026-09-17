import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/phone_formatter.dart';

class SettingAccountScreen extends StatelessWidget {
  const SettingAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser
        : null;
    final rawPhone =
        user?.userMetadata?['phone'] as String? ?? user?.phone ?? '';
    final formattedPhone = PhoneFormatter.formatForDisplay(rawPhone);
    final phoneSubtitle = formattedPhone.isNotEmpty
        ? 'เบอร์โทร: $formattedPhone'
        : 'อีเมล, เบอร์โทรศัพท์';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ตั้งค่าบัญชี',
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
              _SettingItem(
                icon: Icons.person_outline_rounded,
                iconBgColor: const Color(0xFFF3E8FF),
                iconColor: AppColors.primaryColor,
                title: 'แก้ไขข้อมูล',
                subtitle: 'ชื่อแสดงตัวตน, ชื่อผู้ใช้',
                onTap: () => AppRoutes.openEditProfile(context),
              ),
              Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
              _SettingItem(
                icon: Icons.contact_mail_outlined,
                iconBgColor: const Color(0xFFE3F2FF),
                iconColor: const Color(0xFF1976D2),
                title: 'ข้อมูลติดต่อ',
                subtitle: phoneSubtitle,
                onTap: () => AppRoutes.openEditContact(context),
              ),
              Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
              _SettingItem(
                icon: Icons.security_outlined,
                iconBgColor: const Color(0xFFE8F5E9),
                iconColor: const Color(0xFF388E3C),
                title: 'ความปลอดภัยและความเป็นส่วนตัว',
                subtitle: 'รหัสผ่าน, บล็อกผู้ใช้, การแจ้งเตือน',
                showDivider: false,
                onTap: () => AppRoutes.openChangeAccount(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Setting Item Widget ──────────────────────────────────────────────────────

class _SettingItem extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool showDivider;
  final VoidCallback? onTap;

  const _SettingItem({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
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
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
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
