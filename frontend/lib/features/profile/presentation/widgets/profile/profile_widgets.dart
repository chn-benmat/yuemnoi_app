import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/theme/app_text_styles.dart';

// ─── Profile Header ───────────────────────────────────────────────────────────

class ProfileHeader extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final VoidCallback? onProfileTap;

  const ProfileHeader({
    super.key,
    required this.displayName,
    required this.avatarUrl,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Material(
      color: AppColors.primaryColor,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onProfileTap,
        splashColor: Colors.white.withValues(alpha: 0.16),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 28),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: ProfileAvatar(
                  avatarUrl: avatarUrl,
                  displayName: displayName,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'ดูโปรไฟล์',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;

  const ProfileAvatar({
    super.key,
    required this.avatarUrl,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) =>
                    ProfileInitialAvatar(name: displayName),
              )
            : ProfileInitialAvatar(name: displayName),
      ),
    );
  }
}

class ProfileInitialAvatar extends StatelessWidget {
  final String name;
  const ProfileInitialAvatar({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      color: AppColors.gradient2,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class ProfileQuickActionsRow extends StatelessWidget {
  final List<ProfileQuickActionData> items;
  const ProfileQuickActionsRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map((item) => Expanded(child: ProfileQuickActionItem(data: item)))
            .toList(),
      ),
    );
  }
}

class ProfileQuickActionData {
  final IconData? icon;
  final String? imageAsset;
  final String label;
  final VoidCallback? onTap;

  const ProfileQuickActionData({
    this.icon,
    this.imageAsset,
    required this.label,
    this.onTap,
  });
}

class ProfileQuickActionItem extends StatelessWidget {
  final ProfileQuickActionData data;
  const ProfileQuickActionItem({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: data.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: data.imageAsset != null
                  ? Image.asset(
                      data.imageAsset!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) {
                        if (data.imageAsset == 'assets/icons/calendar.png') {
                          return Image.asset(
                            'assets/icons/calender.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              data.icon ?? Icons.category_rounded,
                              color: AppColors.primaryColor,
                              size: 22,
                            ),
                          );
                        }
                        return Icon(
                          data.icon ?? Icons.category_rounded,
                          color: AppColors.primaryColor,
                          size: 22,
                        );
                      },
                    )
                  : Icon(
                      data.icon ?? Icons.category_rounded,
                      color: AppColors.primaryColor,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 10,
              color: AppColors.labelColor,
              height: 1.3,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class ProfileMenuItemData {
  final IconData icon;
  final String title;
  final bool showDivider;
  final VoidCallback? onTap;

  const ProfileMenuItemData({
    required this.icon,
    required this.title,
    this.showDivider = true,
    this.onTap,
  });
}

class ProfileSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<ProfileMenuItemData> items;

  const ProfileSection({
    super.key,
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...items.map((item) => ProfileMenuItem(data: item)),
        ],
      ),
    );
  }
}

class ProfileMenuItem extends StatelessWidget {
  final ProfileMenuItemData data;
  const ProfileMenuItem({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(data.icon, size: 18, color: AppColors.fieldIconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      color: Color(0xFF3A3A3A),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.hintTextColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (data.showDivider)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Colors.grey.shade100,
          ),
      ],
    );
  }
}
