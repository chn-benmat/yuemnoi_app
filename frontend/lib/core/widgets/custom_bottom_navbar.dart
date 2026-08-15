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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: GNav(
            rippleColor: AppColors.primaryColor.withValues(alpha: 0.1),
            hoverColor: AppColors.primaryColor.withValues(alpha: 0.05),
            gap: 8,
            activeColor: AppColors.primaryColor,
            iconSize: 24,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            duration: const Duration(milliseconds: 300),
            tabBackgroundColor: const Color(
              0xFFF3E8FF,
            ), // Light purple for active pill
            color: const Color(0xFF8E8E93), // Medium grey for inactive icons
            selectedIndex: selectedIndex,
            onTabChange: onTabChange,
            textStyle: const TextStyle(
              fontFamily: 'Prompt',
              fontWeight: FontWeight.w600,
              fontSize: 14,
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
                              size: 24,
                              color: selectedIndex == 1
                                  ? AppColors.primaryColor
                                  : const Color(0xFF8E8E93),
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
    );
  }
}
