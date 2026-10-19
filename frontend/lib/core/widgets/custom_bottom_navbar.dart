import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class CustomBottomNavbar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChange;
  final bool hasUnreadChat;
  final bool hasUnreadNotification;

  const CustomBottomNavbar({
    super.key,
    required this.selectedIndex,
    required this.onTabChange,
    this.hasUnreadChat = false,
    this.hasUnreadNotification = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 12.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                // ขาวโปร่งแสงสไตล์ Frosted Glass ที่โปร่งใสและเห็นพื้นหลังด้านหลังชัดเจนขึ้น
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 20,
                    spreadRadius: 1,
                    color: Colors.black.withValues(alpha: 0.06),
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    blurRadius: 6,
                    spreadRadius: -1,
                    color: Colors.black.withValues(alpha: 0.03),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 6.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  _NavItem(
                    key: const ValueKey('nav-home'),
                    label: 'หน้าหลัก',
                    icon: selectedIndex == 0
                        ? Icons.home_rounded
                        : Icons.home_outlined,
                    selected: selectedIndex == 0,
                    onTap: () => onTabChange(0),
                  ),
                  _NavItem(
                    key: const ValueKey('nav-chat'),
                    label: 'แชท',
                    icon: selectedIndex == 1
                        ? Icons.chat_bubble_rounded
                        : Icons.chat_bubble_outline_rounded,
                    selected: selectedIndex == 1,
                    hasUnread: hasUnreadChat,
                    badgeKey: const ValueKey('chat-unread-badge'),
                    onTap: () => onTabChange(1),
                  ),
                  _NavItem(
                    key: const ValueKey('nav-notification'),
                    label: 'แจ้งเตือน',
                    icon: selectedIndex == 2
                        ? Icons.notifications_rounded
                        : Icons.notifications_none_rounded,
                    selected: selectedIndex == 2,
                    hasUnread: hasUnreadNotification,
                    badgeKey: const ValueKey('notification-unread-badge'),
                    onTap: () => onTabChange(2),
                  ),
                  _NavItem(
                    key: const ValueKey('nav-profile'),
                    label: 'โปรไฟล์',
                    icon: selectedIndex == 3
                        ? Icons.person_rounded
                        : Icons.person_outline_rounded,
                    selected: selectedIndex == 3,
                    onTap: () => onTabChange(3),
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

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool hasUnread;
  final Key? badgeKey;
  final VoidCallback onTap;

  const _NavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.hasUnread = false,
    this.badgeKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryColor : const Color(0xFF64748B);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 22, color: color),
                    if (hasUnread)
                      Positioned(
                        top: -2,
                        right: -3,
                        child: Container(
                          key: badgeKey,
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Prompt',
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 10,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
