import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/phone_formatter.dart';
import '../../widgets/account/setting_account_widgets.dart';

class SettingAccountScreen extends StatelessWidget {
  const SettingAccountScreen({super.key});

  void _handleBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      AppRoutes.goToProfile(context);
    }
  }

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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F9),
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          leading: BackButton(onPressed: () => _handleBack(context)),
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
                AccountSettingItem(
                  icon: Icons.person_outline_rounded,
                  iconBgColor: const Color(0xFFF3E8FF),
                  iconColor: AppColors.primaryColor,
                  title: 'แก้ไขข้อมูล',
                  subtitle: 'ชื่อแสดงตัวตน, ชื่อผู้ใช้',
                  onTap: () => AppRoutes.openEditProfile(context),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Colors.grey.shade100,
                ),
                AccountSettingItem(
                  icon: Icons.contact_mail_outlined,
                  iconBgColor: const Color(0xFFE3F2FF),
                  iconColor: const Color(0xFF1976D2),
                  title: 'ข้อมูลติดต่อ',
                  subtitle: phoneSubtitle,
                  onTap: () => AppRoutes.openEditContact(context),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Colors.grey.shade100,
                ),
                AccountSettingItem(
                  icon: Icons.badge_outlined,
                  iconBgColor: const Color(0xFFF3E8FF),
                  iconColor: AppColors.primaryColor,
                  title: 'ข้อมูลบัตรประชาชน',
                  subtitle: 'รูปยืนยันตัวตน, ข้อมูลบัตรและที่อยู่',
                  onTap: () => AppRoutes.openIdentityAccount(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
