import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import '../constants/colors.dart';

class CustomBottomNavbar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChange;
  final bool hasUnreadChat;

  const CustomBottomNavbar({
    super.key,
    required this.selectedIndex,
    required this.onTabChange,
    this.hasUnreadChat = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 12.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                // ขาวโปร่งแสง 92% ให้ฉากหลังเบลอทะลุได้ แต่ไม่จางกลืนไปกับหน้าจอขาว
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(36),
                // เส้นขอบตัดกับพื้นหลังของหน้าแชทได้อย่างคมชัด
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 20,
                    spreadRadius: 1,
                    color: Colors.black.withValues(alpha: 0.10),
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    blurRadius: 6,
                    spreadRadius: -1,
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: GNav(
                rippleColor: AppColors.primaryColor.withValues(alpha: 0.12),
                hoverColor: AppColors.primaryColor.withValues(alpha: 0.05),
                gap: 6,
                activeColor: AppColors.primaryColor,
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                duration: const Duration(milliseconds: 280),
                tabBackgroundColor: const Color(0xFFF3E8FF), // เม็ดยาสีม่วงอ่อนพร้อมยืดข้อความ
                color: const Color(0xFF64748B), // สีไอคอนเทาเข้มคมชัด ไม่จาง
                selectedIndex: selectedIndex,
                onTabChange: onTabChange,
                textStyle: const TextStyle(
                  fontFamily: 'Prompt',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.primaryColor,
                ),
                tabs: [
                  GButton(
                    icon: selectedIndex == 0
                        ? Icons.home_rounded
                        : Icons.home_outlined,
                    text: 'หน้าหลัก',
                  ),
                  GButton(
                    key: const ValueKey('nav-chat'),
                    icon: selectedIndex == 1
                        ? Icons.chat_bubble_rounded
                        : Icons.chat_bubble_outline_rounded,
                    leading: hasUnreadChat
                        ? SizedBox(
                            width: 26,
                            height: 24,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  selectedIndex == 1
                                      ? Icons.chat_bubble_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  size: 22,
                                  color: selectedIndex == 1
                                      ? AppColors.primaryColor
                                      : const Color(0xFF64748B),
                                ),
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    key: const ValueKey('chat-unread-badge'),
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selectedIndex == 1
                                            ? const Color(0xFFF3E8FF)
                                            : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : null,
                    text: 'แชท',
                  ),
                  GButton(
                    icon: selectedIndex == 2
                        ? Icons.account_balance_wallet_rounded
                        : Icons.account_balance_wallet_outlined,
                    text: 'เงินในบัญชี',
                  ),
                  GButton(
                    icon: selectedIndex == 3
                        ? Icons.person_rounded
                        : Icons.person_outline_rounded,
                    text: 'โปรไฟล์',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
