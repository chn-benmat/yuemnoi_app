import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_event.dart';
import 'user_profile_view_screen.dart';
import '../../widgets/profile/profile_widgets.dart';

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
            ProfileHeader(
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
                      child: ProfileQuickActionsRow(
                        items: [
                          ProfileQuickActionData(
                            icon: Icons.inventory_2_outlined,
                            label: 'อุปกรณ์ของฉัน',
                            onTap: () => AppRoutes.openMyItems(context),
                          ),
                          ProfileQuickActionData(
                            icon: Icons.monetization_on_outlined,
                            label: 'รายได้',
                            onTap: () => AppRoutes.openRentalIncome(context),
                          ),
                          ProfileQuickActionData(
                            icon: Icons.local_shipping_outlined,
                            label: 'สถานะการเช่า',
                            onTap: () => AppRoutes.openRentalStatus(context),
                          ),
                          ProfileQuickActionData(
                            icon: Icons.favorite_border_rounded,
                            label: 'ถูกใจ',
                            onTap: () => AppRoutes.openFavorite(context),
                          ),
                          ProfileQuickActionData(
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
                          ProfileSection(
                            icon: Icons.settings_outlined,
                            title: 'การตั้งค่า',
                            items: [
                              ProfileMenuItemData(
                                icon: Icons.manage_accounts_outlined,
                                title: 'ตั้งค่าบัญชี',
                                onTap: () =>
                                    AppRoutes.openSettingAccount(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ProfileSection(
                            icon: Icons.help_outline_rounded,
                            title: 'ศูนย์ช่วยเหลือ',
                            items: [
                              ProfileMenuItemData(
                                icon: Icons.headset_mic_outlined,
                                title: 'ติดต่อเจ้าหน้าที่',
                                onTap: () => AppRoutes.openContact(context),
                              ),
                              ProfileMenuItemData(
                                icon: Icons.quiz_outlined,
                                title: 'คำถามที่พบบ่อย',
                                showDivider: false,
                                onTap: () => AppRoutes.openFaq(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ProfileSection(
                            icon: Icons.security_outlined,
                            title: 'หมวดหมู่ความปลอดภัย',
                            items: const [
                              ProfileMenuItemData(
                                icon: Icons.verified_user_outlined,
                                title: 'การยืนยันตัวตน',
                                showDivider: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ProfileSection(
                            icon: Icons.article_outlined,
                            title: 'เงื่อนไขและนโยบาย',
                            items: [
                              ProfileMenuItemData(
                                icon: Icons.description_outlined,
                                title: 'เงื่อนไขการใช้บริการ',
                                onTap: () =>
                                    AppRoutes.openTermsOfService(context),
                              ),
                              ProfileMenuItemData(
                                icon: Icons.privacy_tip_outlined,
                                title: 'นโยบายความเป็นส่วนตัว',
                                showDivider: false,
                                onTap: () =>
                                    AppRoutes.openPrivacyPolicy(context),
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
