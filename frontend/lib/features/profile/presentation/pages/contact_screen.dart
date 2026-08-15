import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'ติดต่อเจ้าหน้าที่',
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ติดต่อYuemnoi',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 16),
            _ContactItem(
              iconWidget: const Icon(Icons.chat_rounded, color: Color(0xFF0099FF), size: 22),
              iconBgColor: const Color(0xFFE3F2FF),
              title: 'คุยผ่าน Messenger',
              subtitle: 'วันจันทร์-ศุกร์ 10:00-22:00\nเสาร์-อาทิตย์/วันหยุดนักขัตฤกษ์ 10:00-19:00',
              onTap: () => _showSnackBar(context, 'เปิด Messenger...'),
            ),
            _ContactItem(
              iconWidget: const Icon(Icons.email_outlined, color: Color(0xFFE53935), size: 22),
              iconBgColor: const Color(0xFFFFEBEE),
              title: 'ส่งอีเมล',
              subtitle: 'support@yuemnoi.co',
              onTap: () => _showSnackBar(context, 'เปิดอีเมล...'),
            ),
            _ContactItem(
              iconWidget: const Icon(Icons.phone_outlined, color: Color(0xFF43A047), size: 22),
              iconBgColor: const Color(0xFFE8F5E9),
              title: 'โทร',
              subtitle: 'วันจันทร์-ศุกร์ 10:00-22:00\nเสาร์-อาทิตย์/วันหยุดนักขัตฤกษ์ 10:00-19:00',
              onTap: () => _showSnackBar(context, 'โทรออก...'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: AppTextStyles.fontFamily)),
        backgroundColor: AppColors.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  final Widget iconWidget;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactItem({
    required this.iconWidget,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: iconWidget),
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
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: AppColors.labelColor,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.hintTextColor,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
