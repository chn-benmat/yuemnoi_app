import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/user_item.dart';

class UserProfileLoadingSkeleton extends StatelessWidget {
  const UserProfileLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      key: const ValueKey('user-profile-loading-skeleton'),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: const Column(
                children: [
                  SkeletonBox(width: 94, height: 94, shape: BoxShape.circle),
                  SizedBox(height: 14),
                  SkeletonBox(width: 156, height: 22, borderRadius: 11),
                  SizedBox(height: 10),
                  SkeletonBox(width: 116, height: 26, borderRadius: 13),
                  SizedBox(height: 12),
                  SkeletonBox(width: 220, height: 12, borderRadius: 6),
                  SizedBox(height: 18),
                  SkeletonBox(height: 48, borderRadius: 24),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SkeletonBox(width: 190, height: 16, borderRadius: 8),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => const _UserRentalSkeletonCard(),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _UserRentalSkeletonCard extends StatelessWidget {
  const _UserRentalSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SkeletonBox(height: double.infinity, borderRadius: 16),
          ),
          Padding(
            padding: EdgeInsets.all(10),
            child: SkeletonBox(height: 13, borderRadius: 7),
          ),
        ],
      ),
    );
  }
}

// ─── Profile Header ───────────────────────────────────────────────────────────

class UserProfileHeaderSection extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final double rating;
  final bool isVerified;
  final bool isCurrentUser;
  final bool isChatLoading;
  final VoidCallback onEditProfile;
  final VoidCallback? onChat;

  const UserProfileHeaderSection({
    super.key,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.rating,
    required this.isVerified,
    required this.isCurrentUser,
    this.isChatLoading = false,
    required this.onEditProfile,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          // Avatar with gradient ring
          UserProfileGradientAvatar(
            avatarUrl: avatarUrl,
            displayName: displayName,
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            displayName,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 10),

          // Badges row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isVerified) ...[
                UserProfileInfoBadge(
                  icon: Icons.verified_rounded,
                  label: 'ยืนยันตัว',
                  iconColor: AppColors.primaryColor,
                  textColor: AppColors.primaryColor,
                  bgColor: const Color(0xFFF3E8FF),
                ),
                const SizedBox(width: 8),
              ],
              UserProfileInfoBadge(
                icon: Icons.star_rounded,
                label: rating > 0 ? rating.toStringAsFixed(1) : '5.0',
                iconColor: const Color(0xFFFF9800),
                textColor: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
              ),
            ],
          ),

          // Bio
          if (bio != null && bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 13,
                color: AppColors.labelColor,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Action button
          ElevatedButton(
            onPressed: isCurrentUser
                ? onEditProfile
                : (isChatLoading ? null : onChat),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              minimumSize: const Size(double.infinity, 48),
            ),
            child: isChatLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    isCurrentUser ? 'แก้ไขโปรไฟล์' : 'แชทกับ $displayName',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Gradient Avatar ──────────────────────────────────────────────────────────

class UserProfileGradientAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;

  const UserProfileGradientAvatar({
    super.key,
    required this.avatarUrl,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 94,
      height: 94,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.gradient2, AppColors.primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(3.5),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.trim().isNotEmpty
            ? Image.network(
                avatarUrl!.trim(),
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) =>
                    UserProfileInitialCircle(name: displayName),
              )
            : UserProfileInitialCircle(name: displayName),
      ),
    );
  }
}

class UserProfileInitialCircle extends StatelessWidget {
  final String name;
  const UserProfileInitialCircle({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      color: const Color(0xFFF3E8FF),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
          ),
        ),
      ),
    );
  }
}

// ─── Info Badge ───────────────────────────────────────────────────────────────

class UserProfileInfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final Color bgColor;

  const UserProfileInfoBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Rental Item Card ─────────────────────────────────────────────────────────

class UserProfileRentalItemData {
  final int? id;
  final String title;
  final double pricePerDay;
  final double rating;
  final String? imageUrl;
  final IconData iconData;
  final Color colorSeed;

  const UserProfileRentalItemData({
    this.id,
    required this.title,
    required this.pricePerDay,
    required this.rating,
    this.imageUrl,
    required this.iconData,
    required this.colorSeed,
  });

  factory UserProfileRentalItemData.fromUserItem(
    UserItem item,
    IconData iconData,
    Color colorSeed,
  ) {
    return UserProfileRentalItemData(
      id: item.id,
      title: item.title,
      pricePerDay: item.price,
      rating: 4.9,
      imageUrl: item.imageUrl,
      iconData: iconData,
      colorSeed: colorSeed,
    );
  }
}

class UserProfileRentalCard extends StatelessWidget {
  final UserProfileRentalItemData item;
  final double? width;

  const UserProfileRentalCard({super.key, required this.item, this.width});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (item.id != null) {
          AppRoutes.openItemDetail(context, itemId: item.id!);
        }
      },
      child: SizedBox(
        width: width,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image section ──────────────────────────────
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Real Image from Supabase or Fallback
                      if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                        Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => Container(
                            color: item.colorSeed,
                            child: Center(
                              child: Icon(
                                item.iconData,
                                color: Colors.white.withValues(alpha: 0.6),
                                size: 44,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          color: item.colorSeed,
                          child: Center(
                            child: Icon(
                              item.iconData,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 44,
                            ),
                          ),
                        ),
                      // Price badge (bottom left)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.pricePerDay.toInt()} ฿/วัน',
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Rating badge (bottom right)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFF9800),
                                size: 12,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                item.rating > 0
                                    ? item.rating.toStringAsFixed(1)
                                    : '5.0',
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Title section ──────────────────────────────
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
