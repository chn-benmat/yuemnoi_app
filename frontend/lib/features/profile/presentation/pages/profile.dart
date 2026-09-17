import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import 'user_profile_view_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? get _currentUser {
    if (SupabaseConfig.isInitialized) {
      return SupabaseConfig.client.auth.currentUser;
    }
    return null;
  }

  String get _displayName {
    final user = _currentUser;
    if (user == null) return 'ผู้ใช้';
    return user.userMetadata?['display_name'] as String? ??
        user.userMetadata?['full_name'] as String? ??
        user.email?.split('@').first ??
        'ผู้ใช้';
  }

  String? get _avatarUrl {
    final user = _currentUser;
    if (user == null) return null;
    return user.userMetadata?['avatar_url'] as String? ??
        user.userMetadata?['picture'] as String?;
  }

  void _openUserProfile() {
    final user = _currentUser;
    final meta = user?.userMetadata ?? {};
    final bio = (meta['bio'] as String?)?.trim();
    AppRoutes.openUserProfile(
      context,
      args: UserProfileViewArgs(
        userId: user?.id ?? '',
        displayName: _displayName,
        avatarUrl: _avatarUrl,
        rating: 4.9,
        isVerified: true,
        bio: (bio != null && bio.isNotEmpty)
            ? bio
            : 'สนใจกล้องตัวไหนโปรดติดต่อฉัน',
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'ออกจากระบบ',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'คุณต้องการออกจากระบบใช่หรือไม่?',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: AppColors.labelColor,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _performLogout();
            },
            child: const Text(
              'ออกจากระบบ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: AppColors.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _performLogout() async {
    try {
      if (SupabaseConfig.isInitialized) {
        await SupabaseConfig.client.auth.signOut();
      }
    } catch (_) {}
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthResetState());
    AppRoutes.goToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileHeader(
              displayName: _displayName,
              avatarUrl: _avatarUrl,
              onProfileTap: _openUserProfile,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _QuickActionsRow(
                  items: [
                    _QuickActionData(
                      icon: Icons.inventory_2_outlined,
                      label: 'อุปกรณ์ของฉัน',
                      onTap: () => AppRoutes.openMyItems(context),
                    ),
                    _QuickActionData(
                      icon: Icons.monetization_on_outlined,
                      label: 'รายได้',
                      onTap: () => AppRoutes.openRentalIncome(context),
                    ),
                    _QuickActionData(
                      icon: Icons.local_shipping_outlined,
                      label: 'สถานะการเช่า',
                      onTap: () => AppRoutes.openRentalStatus(context),
                    ),
                    _QuickActionData(
                      icon: Icons.favorite_border_rounded,
                      label: 'ถูกใจ',
                      onTap: () => AppRoutes.openFavorite(context),
                    ),
                    _QuickActionData(
                      icon: Icons.calendar_today_outlined,
                      label: 'ประวัติการเช่า',
                      onTap: () => AppRoutes.openRentalHistory(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _ProfileSection(
                      icon: Icons.settings_outlined,
                      title: 'การตั้งค่า',
                      items: [
                        _MenuItemData(
                          icon: Icons.manage_accounts_outlined,
                          title: 'ตั้งค่าบัญชี',
                          onTap: () => AppRoutes.openSettingAccount(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ProfileSection(
                      icon: Icons.help_outline_rounded,
                      title: 'ศูนย์ช่วยเหลือ',
                      items: [
                        _MenuItemData(
                          icon: Icons.headset_mic_outlined,
                          title: 'ติดต่อเจ้าหน้าที่',
                          onTap: () => AppRoutes.openContact(context),
                        ),
                        _MenuItemData(
                          icon: Icons.quiz_outlined,
                          title: 'คำถามที่พบบ่อย',
                          showDivider: false,
                          onTap: () => AppRoutes.openFaq(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ProfileSection(
                      icon: Icons.security_outlined,
                      title: 'หมวดหมู่ความปลอดภัย',
                      items: [
                        _MenuItemData(
                          icon: Icons.assignment_return_outlined,
                          title: 'การคืนอุปกรณ์ (ระบบป้องกันการโกง)',
                          onTap: () => AppRoutes.openRentalReturn(context),
                        ),
                        const _MenuItemData(
                          icon: Icons.verified_user_outlined,
                          title: 'การยืนยันตัวตน',
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ProfileSection(
                      icon: Icons.article_outlined,
                      title: 'เงื่อนไขและนโยบาย',
                      items: [
                        _MenuItemData(
                          icon: Icons.description_outlined,
                          title: 'เงื่อนไขการใช้บริการ',
                          onTap: () => AppRoutes.openTermsOfService(context),
                        ),
                        _MenuItemData(
                          icon: Icons.privacy_tip_outlined,
                          title: 'นโยบายความเป็นส่วนตัว',
                          showDivider: false,
                          onTap: () => AppRoutes.openPrivacyPolicy(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'ออกจากระบบ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
          ],
        ),
      ),
    );
  }
}

// ─── Profile Header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final VoidCallback? onProfileTap;

  const _ProfileHeader({
    required this.displayName,
    required this.avatarUrl,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryColor, AppColors.gradient1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onProfileTap,
            child: Row(
              children: [
                _AvatarWidget(avatarUrl: avatarUrl, displayName: displayName),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'ดูโปรไฟล์',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          color: Colors.white70,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;

  const _AvatarWidget({required this.avatarUrl, required this.displayName});

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
                    _InitialAvatar(name: displayName),
              )
            : _InitialAvatar(name: displayName),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String name;
  const _InitialAvatar({required this.name});

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

class _QuickActionsRow extends StatelessWidget {
  final List<_QuickActionData> items;
  const _QuickActionsRow({required this.items});

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
            .map((item) => Expanded(child: _QuickActionItem(data: item)))
            .toList(),
      ),
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickActionData({required this.icon, required this.label, this.onTap});
}

class _QuickActionItem extends StatelessWidget {
  final _QuickActionData data;
  const _QuickActionItem({required this.data});

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
            child: Icon(data.icon, color: AppColors.primaryColor, size: 22),
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

class _MenuItemData {
  final IconData icon;
  final String title;
  final bool showDivider;
  final VoidCallback? onTap;

  const _MenuItemData({
    required this.icon,
    required this.title,
    this.showDivider = true,
    this.onTap,
  });
}

class _ProfileSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_MenuItemData> items;

  const _ProfileSection({
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
          ...items.map((item) => _MenuItem(data: item)),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final _MenuItemData data;
  const _MenuItem({required this.data});

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
