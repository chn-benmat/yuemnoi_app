import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import '../../../../../core/network/auth_session.dart';
import '../../../../../core/services/fcm_service.dart';
import '../../../../../core/services/favorite_service.dart';
import '../../../../../core/utils/auth_guard.dart';
import '../../../../auth/presentation/bloc/auth_event.dart';
import 'user_profile_view_screen.dart';
import '../../widgets/profile/profile_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _guestPromptOpen = false;
  bool _guestPromptScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleGuestPrompt();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _scheduleGuestPrompt();
  }

  void _scheduleGuestPrompt() {
    if (!widget.isActive || _guestPromptScheduled || _guestPromptOpen) return;
    _guestPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guestPromptScheduled = false;
      if (mounted &&
          widget.isActive &&
          _currentUser == null &&
          ModalRoute.of(context)?.isCurrent != false) {
        _showGuestLogin();
      }
    });
  }

  Future<void> _showGuestLogin() async {
    if (!mounted ||
        !widget.isActive ||
        _currentUser != null ||
        _guestPromptOpen) {
      return;
    }
    _guestPromptOpen = true;
    try {
      await AuthGuard.requireAuth(context);
      if (mounted) setState(() {});
    } finally {
      _guestPromptOpen = false;
    }
  }

  User? get _currentUser {
    if (SupabaseConfig.isInitialized) {
      return SupabaseConfig.client.auth.currentUser;
    }
    return null;
  }

  String get _displayName {
    final user = _currentUser;
    if (user == null) return 'ผู้เยี่ยมชม (Guest)';
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

  Future<void> _handleMyItems() async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อดูอุปกรณ์',
      message: 'กรุณาเข้าสู่ระบบก่อนจัดการอุปกรณ์ที่คุณปล่อยเช่า',
    );
    if (authed && mounted) {
      AppRoutes.openMyItems(context);
    }
  }

  Future<void> _handleRentalIncome() async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อดูรายได้',
      message: 'กรุณาเข้าสู่ระบบก่อนดูรายได้จากการปล่อยเช่า',
    );
    if (authed && mounted) {
      AppRoutes.openRentalIncome(context);
    }
  }

  Future<void> _handleRentalStatus() async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อดูสถานะ',
      message: 'กรุณาเข้าสู่ระบบก่อนตรวจสอบสถานะการเช่า',
    );
    if (authed && mounted) {
      AppRoutes.openRentalStatus(context);
    }
  }

  Future<void> _handleRentalHistory() async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อดูประวัติ',
      message: 'กรุณาเข้าสู่ระบบก่อนดูประวัติการเช่า',
    );
    if (authed && mounted) {
      AppRoutes.openRentalHistory(context);
    }
  }

  Future<void> _handleSettingAccount() async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบ',
      message: 'กรุณาเข้าสู่ระบบก่อนเข้าสู่หน้าตั้งค่าบัญชี',
    );
    if (authed && mounted) {
      await AppRoutes.openSettingAccount(context);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _handlePrivacy({bool notificationsOnly = false}) async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบ',
      message: 'กรุณาเข้าสู่ระบบก่อนจัดการความเป็นส่วนตัว',
    );
    if (!authed || !mounted) return;
    if (notificationsOnly) {
      await AppRoutes.openNotificationSettings(context);
    } else {
      await AppRoutes.openChangeAccount(context);
    }
  }

  void _openUserProfile() async {
    final user = _currentUser;
    if (user == null) {
      await _showGuestLogin();
      return;
    }
    if (!mounted) return;
    AppRoutes.openUserProfile(
      context,
      args: UserProfileViewArgs(
        userId: user.id,
        displayName: _displayName,
        avatarUrl: _avatarUrl,
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
    await FcmService.instance.unregisterCurrentDevice();
    try {
      if (SupabaseConfig.isInitialized) {
        await SupabaseConfig.client.auth.signOut();
      }
    } catch (_) {}
    AuthSession.clear(purgeCache: true);
    unawaited(FavoriteService.instance.init(forceRefresh: true));
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthResetState());
    setState(() {});
    _scheduleGuestPrompt();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (mounted) setState(() {});
      },
      child: Container(
        color: const Color(0xFFF7F6FA),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileHeader(
              displayName: _displayName,
              avatarUrl: _avatarUrl,
              onProfileTap: _openUserProfile,
              isGuest: _currentUser == null,
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        'การใช้งานของคุณ',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF30263E),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ProfileQuickActionsRow(
                        items: [
                          ProfileQuickActionData(
                            icon: Icons.inventory_2_outlined,
                            label: 'อุปกรณ์ของฉัน',
                            onTap: _handleMyItems,
                          ),
                          ProfileQuickActionData(
                            icon: Icons.monetization_on_outlined,
                            label: 'รายได้',
                            onTap: _handleRentalIncome,
                          ),
                          ProfileQuickActionData(
                            icon: Icons.local_shipping_outlined,
                            label: 'สถานะการเช่า',
                            onTap: _handleRentalStatus,
                          ),
                          ProfileQuickActionData(
                            icon: Icons.calendar_today_outlined,
                            label: 'ประวัติการเช่า',
                            onTap: _handleRentalHistory,
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
                                onTap: _handleSettingAccount,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ProfileSection(
                            icon: Icons.privacy_tip_outlined,
                            title: 'ความเป็นส่วนตัว',
                            items: [
                              ProfileMenuItemData(
                                icon: Icons.shield_outlined,
                                title: 'ศูนย์ความเป็นส่วนตัว',
                                onTap: () => _handlePrivacy(),
                              ),
                              ProfileMenuItemData(
                                icon: Icons.notifications_outlined,
                                title: 'การแจ้งเตือน',
                                showDivider: false,
                                onTap: () =>
                                    _handlePrivacy(notificationsOnly: true),
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
                          if (_currentUser != null) ...[
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _logout,
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  size: 18,
                                ),
                                label: const Text('ออกจากระบบ'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFB42342),
                                  minimumSize: const Size(0, 52),
                                  side: const BorderSide(
                                    color: Color(0xFFF2D4DC),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 110),
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
