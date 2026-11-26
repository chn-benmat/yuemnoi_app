import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/profile_storefront.dart';
import '../../../domain/entities/user_item.dart';

const _ink = Color(0xFF24212C);
const _muted = Color(0xFF706B79);
const _line = Color(0xFFECEAF0);
const _text = TextStyle(fontFamily: AppTextStyles.fontFamily, color: _ink);

class UserProfileHeaderSection extends StatelessWidget {
  const UserProfileHeaderSection({
    super.key,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.reviews,
    required this.isVerified,
    required this.isCurrentUser,
    required this.onEditProfile,
    this.onReviewsTap,
  });

  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final ReviewSummary? reviews;
  final bool isVerified;
  final bool isCurrentUser;
  final VoidCallback onEditProfile;
  final VoidCallback? onReviewsTap;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileAvatar(avatarUrl: avatarUrl, name: displayName),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'เจ้าของอุปกรณ์',
                    style: _text.copyWith(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    displayName,
                    style: _text.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    button: true,
                    label: 'ดูรีวิวทั้งหมด',
                    child: InkWell(
                      key: const ValueKey('profile-reviews'),
                      onTap: onReviewsTap,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: _ReviewLabel(reviews: reviews)),
                            if (onReviewsTap != null) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: _muted,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(height: 8),
                    const _VerifiedLabel(),
                  ],
                  if (isCurrentUser) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('edit-storefront-profile'),
                      onPressed: onEditProfile,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('แก้ไขโปรไฟล์'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryColor,
                        side: const BorderSide(color: Color(0xFFE2D5F0)),
                        textStyle: _text.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (bio != null && bio!.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            bio!.trim(),
            style: _text.copyWith(fontSize: 13, color: _muted, height: 1.65),
          ),
        ],
      ],
    ),
  );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.avatarUrl, required this.name});
  final String? avatarUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: const Color(0xFFF1EAF8),
      child: Center(
        child: Text(
          name.isEmpty ? 'Y' : name.characters.first.toUpperCase(),
          style: _text.copyWith(
            fontSize: 28,
            color: AppColors.primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return SizedBox.square(
      dimension: 76,
      child: ClipOval(
        child: avatarUrl == null || avatarUrl!.trim().isEmpty
            ? fallback
            : Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _VerifiedLabel extends StatelessWidget {
  const _VerifiedLabel();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        Icons.verified_outlined,
        size: 15,
        color: AppColors.primaryColor,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          'ยืนยันตัวตนแล้ว',
          style: _text.copyWith(fontSize: 12, color: AppColors.primaryColor),
        ),
      ),
    ],
  );
}

class _ReviewLabel extends StatelessWidget {
  const _ReviewLabel({required this.reviews, this.small = false});
  final ReviewSummary? reviews;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = _text.copyWith(
      fontSize: small ? 11 : 13,
      color: _muted,
      height: 1.5,
    );
    if (reviews == null) return Text('โหลดคะแนนไม่สำเร็จ', style: style);
    if (reviews!.count == 0) return Text('ยังไม่มีรีวิว', style: style);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.star_rounded,
          size: small ? 16 : 19,
          color: const Color(0xFFC58313),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: reviews!.average.toStringAsFixed(1),
                  style: style.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' (${reviews!.count} รีวิว)', style: style),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class UserProfileRentalCard extends StatelessWidget {
  const UserProfileRentalCard({super.key, required this.item});
  final StorefrontItem item;

  String get _unit => switch (item.rentalType.toLowerCase()) {
    'รายชั่วโมง' || 'hour' || 'hourly' => 'ชั่วโมง',
    'รายวัน' || 'day' || 'daily' => 'วัน',
    'รายสัปดาห์' || 'week' || 'weekly' => 'สัปดาห์',
    'รายเดือน' || 'month' || 'monthly' => 'เดือน',
    _ => item.rentalType.isEmpty ? 'ไม่ระบุหน่วย' : item.rentalType,
  };

  (String, bool) get _availability => switch (item.item.listingStatus) {
    UserItemStatus.rented => ('กำลังถูกเช่า', false),
    UserItemStatus.available => ('พร้อมให้เช่า', true),
    UserItemStatus.unavailable => ('ยังไม่พร้อมให้เช่า', false),
    UserItemStatus.maintenance => ('อยู่ระหว่างดูแล', false),
    _ => (item.status.isEmpty ? 'ไม่ระบุสถานะ' : item.status, false),
  };

  @override
  Widget build(BuildContext context) {
    final info = item.item;
    final (status, available) = _availability;
    final fallback = ColoredBox(
      color: const Color(0xFFF2F1F5),
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 36,
          color: _muted.withValues(alpha: .55),
        ),
      ),
    );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: info.id == null
            ? null
            : () => AppRoutes.openItemDetail(context, itemId: info.id!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: info.imageUrl == null || info.imageUrl!.isEmpty
                    ? fallback
                    : Image.network(
                        info.imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(14) * 3,
                    child: Text(
                      info.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _text.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '฿${NumberFormat('#,##0.##').format(info.price)}',
                          style: _text.copyWith(
                            fontSize: 17,
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: ' / $_unit',
                          style: _text.copyWith(fontSize: 11, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  _ReviewLabel(reviews: item.reviews, small: true),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: available ? const Color(0xFF348265) : _muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          status,
                          style: _text.copyWith(
                            fontSize: 11,
                            color: _muted,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserProfileChatBar extends StatelessWidget {
  const UserProfileChatBar({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });
  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: FilledButton.icon(
          key: const ValueKey('storefront-chat'),
          onPressed: isLoading ? null : onPressed,
          icon: isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.chat_bubble_outline_rounded, size: 20),
          label: Text(isLoading ? 'กำลังเปิดแชท…' : 'แชทกับเจ้าของ'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: _text.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ),
  );
}

class UserProfileRetryBanner extends StatelessWidget {
  const UserProfileRetryBanner({
    super.key,
    required this.message,
    required this.onRetry,
    this.isLoading = false,
  });
  final String message;
  final VoidCallback onRetry;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1EBF7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: _text.copyWith(fontSize: 12, color: _muted),
              ),
            ),
            TextButton(
              onPressed: isLoading ? null : onRetry,
              child: Text(isLoading ? 'กำลังโหลด…' : 'ลองใหม่'),
            ),
          ],
        ),
      ),
    ),
  );
}

class UserProfileMessage extends StatelessWidget {
  const UserProfileMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onPressed,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    child: Column(
      children: [
        const SizedBox(height: 20),
        Icon(icon, size: 36, color: const Color(0xFF9D8AAD)),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: _text.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: _text.copyWith(fontSize: 13, color: _muted),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onPressed, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class UserProfileLoadingSkeleton extends StatelessWidget {
  const UserProfileLoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => SkeletonShimmer(
    key: const ValueKey('user-profile-loading-skeleton'),
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 76, height: 76, shape: BoxShape.circle),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 100, height: 12),
                  SizedBox(height: 12),
                  SkeletonBox(height: 24),
                  SizedBox(height: 12),
                  SkeletonBox(width: 100, height: 14),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        const SkeletonBox(width: 180, height: 18),
        const SizedBox(height: 20),
        for (var i = 0; i < 2; i++) ...[
          Row(
            children: [
              for (var col = 0; col < 2; col++) ...[
                if (col == 1) const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: SkeletonBox(
                          height: double.infinity,
                          borderRadius: 16,
                        ),
                      ),
                      SizedBox(height: 12),
                      SkeletonBox(height: 16),
                      SizedBox(height: 12),
                      SkeletonBox(height: 16),
                      SizedBox(height: 12),
                      SkeletonBox(height: 12),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
        ],
      ],
    ),
  );
}
