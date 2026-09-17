import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/utils/auth_guard.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/utils/phone_formatter.dart';
import '../../../../chat/data/repositories/chat_repository_impl.dart';
import '../../../data/repositories/profile_repository_impl.dart';
import '../../../data/repositories/user_items_repository_impl.dart';
import '../../../domain/usecases/get_my_items_usecase.dart';
import '../../../domain/usecases/get_user_profile_usecase.dart';
import '../../widgets/profile/user_profile_widgets.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

/// ข้อมูลสำหรับแสดงโปรไฟล์สาธารณะของผู้ใช้
class UserProfileViewArgs {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final double rating;
  final bool isVerified;
  final String? bio;

  const UserProfileViewArgs({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.rating = 0.0,
    this.isVerified = false,
    this.bio,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class UserProfileViewScreen extends StatefulWidget {
  final UserProfileViewArgs args;
  final GetUserProfileUseCase? getUserProfileUseCase;
  final GetMyItemsUseCase? getMyItemsUseCase;

  const UserProfileViewScreen({
    super.key,
    required this.args,
    this.getUserProfileUseCase,
    this.getMyItemsUseCase,
  });

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  late final GetUserProfileUseCase _getUserProfileUseCase;
  late final GetMyItemsUseCase _getMyItemsUseCase;
  bool _isLoading = true;
  bool _isChatLoading = false;
  String _displayName = '';
  String? _avatarUrl;
  String? _bio;
  double _rating = 0.0;
  bool _isVerified = false;

  final List<UserProfileRentalItemData> _featuredItems = [];
  List<UserProfileRentalItemData> _userItems = [];

  @override
  void initState() {
    super.initState();
    _displayName = widget.args.displayName;
    _avatarUrl = widget.args.avatarUrl;
    _bio = widget.args.bio;
    _rating = widget.args.rating > 0 ? widget.args.rating : 4.9;
    _isVerified = widget.args.isVerified;

    _getUserProfileUseCase = widget.getUserProfileUseCase ??
        GetUserProfileUseCase(ProfileRepositoryImpl());
    _getMyItemsUseCase = widget.getMyItemsUseCase ??
        GetMyItemsUseCase(UserItemsRepositoryImpl());

    _loadData();
  }

  Future<void> _loadData() async {
    final currentUserId = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    final targetUserId = widget.args.userId.isNotEmpty
        ? widget.args.userId
        : currentUserId ?? '';

    try {
      if (targetUserId.isNotEmpty) {
        // 1. ดึงโปรไฟล์ผ่าน UseCase
        try {
          final profile =
              await _getUserProfileUseCase.execute(userId: targetUserId);
          if (profile.displayName.isNotEmpty) {
            _displayName = profile.displayName;
          }
          if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
            _avatarUrl = profile.avatarUrl;
          }
          if (profile.bio.isNotEmpty) {
            _bio = profile.bio;
          }
          if (profile.rating > 0) {
            _rating = profile.rating;
          }
          _isVerified = profile.isVerified;
        } catch (_) {}

        // 2. ดึงรายการอุปกรณ์ของผู้ใช้ผ่าน UseCase
        try {
          final items = await _getMyItemsUseCase.execute(targetUserId);
          _userItems = items.map((it) {
            final (iconData, colorSeed) = _mapCategoryToStyle(it.category);
            return UserProfileRentalItemData.fromUserItem(
              it,
              iconData,
              colorSeed,
            );
          }).toList();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  (IconData, Color) _mapCategoryToStyle(String? category) {
    if (category == null) {
      return (Icons.devices_other_outlined, const Color(0xFF1A1A2E));
    }
    final cat = category.toLowerCase();
    if (cat.contains('กล้อง') || cat.contains('camera')) {
      return (Icons.camera_alt_outlined, const Color(0xFF1A0038));
    }
    if (cat.contains('โดรน') || cat.contains('drone')) {
      return (Icons.flight_takeoff_outlined, const Color(0xFF00112B));
    }
    if (cat.contains('โทรศัพท์') ||
        cat.contains('มือถือ') ||
        cat.contains('phone')) {
      return (Icons.smartphone_outlined, const Color(0xFF0F172A));
    }
    if (cat.contains('คอมพิวเตอร์') ||
        cat.contains('โน้ตบุ๊ก') ||
        cat.contains('laptop') ||
        cat.contains('macbook')) {
      return (Icons.laptop_mac_outlined, const Color(0xFF1E1B4B));
    }
    if (cat.contains('เสียง') ||
        cat.contains('ลำโพง') ||
        cat.contains('audio')) {
      return (Icons.speaker_outlined, const Color(0xFF14532D));
    }
    if (cat.contains('แคมป์') || cat.contains('เต็นท์')) {
      return (Icons.terrain_outlined, const Color(0xFF064E3B));
    }
    if (cat.contains('รถ') || cat.contains('ยานยนต์')) {
      return (Icons.directions_car_outlined, const Color(0xFF1C1917));
    }
    if (cat.contains('เครื่องมือ') ||
        cat.contains('ทำความสะอาด') ||
        cat.contains('tool')) {
      return (Icons.build_outlined, const Color(0xFF312E81));
    }
    if (cat.contains('เสื้อ') || cat.contains('สูท')) {
      return (Icons.checkroom_outlined, const Color(0xFF152030));
    }
    return (Icons.inventory_2_outlined, const Color(0xFF2E1065));
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
        itemId: _userItems.isNotEmpty ? _userItems.first.id : null,
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = SupabaseConfig.isInitialized
        ? SupabaseConfig.client.auth.currentUser?.id
        : null;
    final isCurrentUser =
        currentUid != null &&
        currentUid.isNotEmpty &&
        currentUid == widget.args.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryColor, AppColors.gradient1],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: const BackButton(),
        title: const Text(
          'Yuemnoi',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const UserProfileLoadingSkeleton()
          : RefreshIndicator(
              color: AppColors.primaryColor,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Profile header ───────────────────────────────────
                    UserProfileHeaderSection(
                      displayName: _displayName,
                      avatarUrl: _avatarUrl,
                      bio: _bio,
                      rating: _rating,
                      isVerified: _isVerified,
                      isCurrentUser: isCurrentUser,
                      isChatLoading: _isChatLoading,
                      onEditProfile: () async {
                        await AppRoutes.openEditProfile(context);
                        _loadData();
                      },
                      onChat: _handleChatPressed,
                    ),

                    const SizedBox(height: 20),

                    // ── Featured rentals (Marketplace) ───────────────────
                    if (_featuredItems.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'รายการเช่าที่น่าสนใจสำหรับคุณ',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 192,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _featuredItems.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) =>
                              UserProfileRentalCard(
                                item: _featuredItems[index],
                                width: 158,
                              ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],

                    // ── All items grid (User's items) ───────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'อุปกรณ์ที่ปล่อยเช่าทั้งหมด',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          if (_userItems.isNotEmpty)
                            Text(
                              '${_userItems.length} รายการ',
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                color: AppColors.hintTextColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_userItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 28,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF3E8FF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.inventory_2_outlined,
                                  color: AppColors.primaryColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                isCurrentUser
                                    ? 'คุณยังไม่มีอุปกรณ์ที่ปล่อยเช่า'
                                    : 'ยังไม่มีอุปกรณ์ที่ปล่อยเช่าในขณะนี้',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isCurrentUser
                                    ? 'นำอุปกรณ์ที่คุณมีมาปล่อยเช่าเพื่อสร้างรายได้ง่ายๆ'
                                    : 'ผู้ใช้นี้ยังไม่ได้ลงประกาศปล่อยเช่าอุปกรณ์ใดๆ',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12,
                                  color: AppColors.hintTextColor,
                                ),
                              ),
                              if (isCurrentUser) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await AppRoutes.openAddRentalItem(context);
                                    _loadData();
                                  },
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text(
                                    'ลงประกาศอุปกรณ์',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.82,
                            ),
                        itemCount: _userItems.length,
                        itemBuilder: (context, index) =>
                            UserProfileRentalCard(item: _userItems[index]),
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
    );
  }
}
