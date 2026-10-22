import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/utils/auth_guard.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/phone_formatter.dart';
import '../../../../chat/data/repositories/chat_repository_impl.dart';
import '../../../data/repositories/profile_storefront_repository_impl.dart';
import '../../../domain/usecases/get_profile_storefront_usecase.dart';
import '../../bloc/profile_storefront_cubit.dart';
import '../../widgets/profile/user_profile_widgets.dart';
import '../../widgets/profile/profile_reviews_sheet.dart';

/// ข้อมูลสำหรับแสดงโปรไฟล์สาธารณะของผู้ใช้
class UserProfileViewArgs {
  final String userId;
  final String displayName;
  final String? avatarUrl;

  const UserProfileViewArgs({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });
}

class UserProfileViewScreen extends StatefulWidget {
  const UserProfileViewScreen({
    super.key,
    required this.args,
    this.getStorefront,
  });

  final UserProfileViewArgs args;
  final GetProfileStorefrontUseCase? getStorefront;

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  late final ProfileStorefrontCubit _storefront;
  bool _isChatLoading = false;

  String get _displayName {
    final loaded = _storefront.state.data?.identity?.displayName ?? '';
    if (loaded.isNotEmpty) return loaded;
    return widget.args.displayName.isNotEmpty
        ? widget.args.displayName
        : 'เจ้าของอุปกรณ์';
  }

  String? get _avatarUrl =>
      _storefront.state.data?.identity?.avatarUrl ?? widget.args.avatarUrl;

  @override
  void initState() {
    super.initState();
    final currentUid = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    _storefront = ProfileStorefrontCubit(
      userId: widget.args.userId.isNotEmpty
          ? widget.args.userId
          : currentUid ?? '',
      getStorefront:
          widget.getStorefront ??
          GetProfileStorefrontUseCase(ProfileStorefrontRepositoryImpl()),
    )..load();
  }

  @override
  void dispose() {
    _storefront.close();
    super.dispose();
  }

  bool _hasCurrentUserPhone() {
    if (!SupabaseConfig.isInitialized) return false;

    final user = SupabaseConfig.client.auth.currentUser;
    final rawPhone =
        user?.userMetadata?['phone']?.toString() ?? user?.phone ?? '';
    return PhoneFormatter.isValidPhone(rawPhone);
  }

  Future<void> _showMissingPhoneDialog() async {
    final shouldAddPhone = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'เพิ่มเบอร์โทรศัพท์',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'กรุณาใส่เบอร์โทรศัพท์สำหรับการติดต่อก่อนใช้งานแชท',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
            child: const Text('เพิ่มเบอร์โทร'),
          ),
        ],
      ),
    );

    if (shouldAddPhone == true && mounted) {
      await AppRoutes.openEditContact(context);
    }
  }

  Future<void> _handleChatPressed() async {
    final authed = await AuthGuard.requireAuth(
      context,
      title: 'เข้าสู่ระบบเพื่อใช้งานแชท',
      message: 'กรุณาเข้าสู่ระบบก่อนเริ่มการสนทนากับผู้ใช้นี้',
    );
    if (!authed || !mounted) {
      return;
    }

    final currentUid = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    final targetUserId = widget.args.userId;

    if (currentUid != null && currentUid == targetUserId) {
      setState(() {});
      await _storefront.load();
      return;
    }

    if (!_hasCurrentUserPhone()) {
      await _showMissingPhoneDialog();
      return;
    }

    setState(() => _isChatLoading = true);

    try {
      final repository = ChatRepositoryImpl();
      final conversation = await repository.getOrCreateConversation(
        ownerId: targetUserId,
        itemId: _storefront.state.data?.items.firstOrNull?.item.id,
      );

      final effectiveConversation = conversation.copyWith(
        name: (_displayName.isNotEmpty && _displayName != 'ผู้ใช้')
            ? _displayName
            : conversation.name,
        avatarAsset: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
            ? _avatarUrl
            : conversation.avatarAsset,
      );

      if (mounted) {
        setState(() => _isChatLoading = false);
        await AppRoutes.openConversation(
          context,
          conversation: effectiveConversation,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isChatLoading = false);
        showAppPopup(context, content: Text(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    final isCurrentUser =
        currentUid != null && currentUid == _storefront.userId;

    return BlocBuilder<ProfileStorefrontCubit, ProfileStorefrontState>(
      bloc: _storefront,
      builder: (context, state) {
        final data = state.data;
        return Scaffold(
          backgroundColor: const Color(0xFFF8F8FA),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            foregroundColor: const Color(0xFF22212A),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: const BackButton(),
            title: const Text(
              'โปรไฟล์',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
          ),
          bottomNavigationBar:
              !isCurrentUser &&
                  _storefront.userId.isNotEmpty &&
                  _storefront.userId != 'unknown'
              ? UserProfileChatBar(
                  isLoading: _isChatLoading,
                  onPressed: _handleChatPressed,
                )
              : null,
          body: state.isLoading && data == null
              ? const UserProfileLoadingSkeleton()
              : RefreshIndicator(
                  color: AppColors.primaryColor,
                  onRefresh: _storefront.load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: UserProfileHeaderSection(
                          displayName: _displayName,
                          avatarUrl: _avatarUrl,
                          bio: data?.identity?.bio,
                          reviews: data?.reviews,
                          onReviewsTap: data?.reviews == null
                              ? null
                              : () => showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  showDragHandle: true,
                                  useSafeArea: true,
                                  builder: (_) =>
                                      ProfileReviewsSheet(storefront: data!),
                                ),
                          isVerified: data?.identity?.isVerified ?? false,
                          isCurrentUser: isCurrentUser,
                          onEditProfile: () async {
                            await AppRoutes.openEditProfile(context);
                            if (mounted) await _storefront.load();
                          },
                        ),
                      ),
                      if (state.hasError ||
                          data?.identityUnavailable == true ||
                          (data != null && data.reviews == null))
                        SliverToBoxAdapter(
                          child: UserProfileRetryBanner(
                            message: state.hasError
                                ? (data == null
                                      ? 'โหลดโปรไฟล์ไม่สำเร็จ'
                                      : 'อัปเดตข้อมูลไม่สำเร็จ กำลังแสดงข้อมูลล่าสุดที่โหลดได้')
                                : data!.identityUnavailable
                                ? 'โหลดข้อมูลเจ้าของไม่ครบ'
                                : 'โหลดคะแนนรีวิวไม่สำเร็จ',
                            isLoading: state.isLoading,
                            onRetry: _storefront.load,
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'อุปกรณ์ให้เช่า',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF22212A),
                                  ),
                                ),
                              ),
                              if (data != null)
                                Text(
                                  '${data.items.length} รายการ',
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 13,
                                    color: Color(0xFF74717D),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (data == null)
                        SliverToBoxAdapter(
                          child: UserProfileMessage(
                            icon: Icons.cloud_off_outlined,
                            title: 'ยังแสดงอุปกรณ์ไม่ได้',
                            message: 'ตรวจสอบการเชื่อมต่อ แล้วลองอีกครั้ง',
                            actionLabel: 'ลองใหม่',
                            onPressed: _storefront.load,
                          ),
                        )
                      else if (data.items.isEmpty)
                        SliverToBoxAdapter(
                          child: UserProfileMessage(
                            icon: Icons.inventory_2_outlined,
                            title: 'ยังไม่มีอุปกรณ์ให้เช่า',
                            message: isCurrentUser
                                ? 'เริ่มปล่อยเช่าอุปกรณ์ชิ้นแรกของคุณ'
                                : 'กลับมาดูอุปกรณ์ของเจ้าของคนนี้ได้ภายหลัง',
                            actionLabel: isCurrentUser ? 'เพิ่มอุปกรณ์' : null,
                            onPressed: isCurrentUser
                                ? () async {
                                    await AppRoutes.openAddRentalItem(context);
                                    if (mounted) await _storefront.load();
                                  }
                                : null,
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.separated(
                            itemCount: (data.items.length / 2).ceil(),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, row) => Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: UserProfileRentalCard(
                                    item: data.items[row * 2],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: row * 2 + 1 < data.items.length
                                      ? UserProfileRentalCard(
                                          item: data.items[row * 2 + 1],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 24 + MediaQuery.paddingOf(context).bottom,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
