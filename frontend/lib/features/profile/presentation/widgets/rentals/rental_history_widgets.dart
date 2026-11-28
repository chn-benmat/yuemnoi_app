import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/rental_booking.dart';

class RentalHistoryLoadingSkeleton extends StatelessWidget {
  const RentalHistoryLoadingSkeleton({super.key, this.count = 6});

  /// จำนวนรายการที่หน้านี้แสดงครั้งล่าสุด ให้ skeleton มีจำนวนเท่าข้อมูลจริง
  final int count;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      key: const ValueKey('rental-history-loading-skeleton'),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => const _RentalHistorySkeletonCard(),
      ),
    );
  }
}

class _RentalHistorySkeletonCard extends StatelessWidget {
  const _RentalHistorySkeletonCard();

  @override
  Widget build(BuildContext context) {
    // กรอบ เงา และแถวรีวิวท้ายการ์ดเหมือน RentalHistoryCard ที่คืนของแล้ว
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 56, height: 56, borderRadius: 14),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.85,
                        child: SkeletonBox(height: 16, borderRadius: 8),
                      ),
                      SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.6,
                        child: SkeletonBox(height: 12, borderRadius: 6),
                      ),
                      SizedBox(height: 9),
                      FractionallySizedBox(
                        widthFactor: 0.5,
                        child: SkeletonBox(height: 11, borderRadius: 5),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                SkeletonBox(width: 60, height: 24, borderRadius: 8),
              ],
            ),
            SizedBox(height: 14),
            SkeletonBox(height: 1, borderRadius: 0),
            SizedBox(height: 10),
            Row(
              children: [
                SkeletonBox(width: 18, height: 18, shape: BoxShape.circle),
                SizedBox(width: 6),
                SkeletonBox(width: 120, height: 12, borderRadius: 5),
                Spacer(),
                SkeletonBox(width: 96, height: 36, borderRadius: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class RentalHistoryItemData {
  final int? bookingId;
  final int? itemId;
  final String? imageUrl;
  final String title;
  final String? ownerId;
  final String ownerName;
  final String duration;
  final String date;
  final String status;
  final Color statusColor;
  final Color statusBgColor;
  final IconData iconData;
  final bool isCompleted;
  final bool alreadyReviewed;

  RentalHistoryItemData({
    this.bookingId,
    this.itemId,
    this.imageUrl,
    required this.title,
    this.ownerId,
    required this.ownerName,
    required this.duration,
    required this.date,
    required this.status,
    required this.statusColor,
    required this.statusBgColor,
    required this.iconData,
    this.isCompleted = false,
    this.alreadyReviewed = false,
  });

  factory RentalHistoryItemData.fromEntity(
    RentalBooking entity,
    Color statusColor,
    Color statusBgColor,
    IconData iconData,
  ) {
    String dateStr = '';
    if (entity.startDate != null) {
      dateStr =
          '${entity.startDate!.day}/${entity.startDate!.month}/${entity.startDate!.year}';
    }
    return RentalHistoryItemData(
      bookingId: entity.bookingId,
      itemId: entity.itemId,
      imageUrl: entity.imageUrl,
      title: entity.title,
      ownerId: entity.partnerId,
      ownerName: entity.partnerName,
      duration: entity.duration,
      date: dateStr,
      status: entity.status,
      statusColor: statusColor,
      statusBgColor: statusBgColor,
      iconData: iconData,
      isCompleted: _isCompletedStatus(entity.statusCode),
    );
  }

  static bool _isCompletedStatus(String value) {
    final status = value.toLowerCase().trim();
    return status == 'completed' || status == 'finished';
  }
}

// ─── Card Widget ──────────────────────────────────────────────────────────────

class RentalHistoryCard extends StatelessWidget {
  final RentalHistoryItemData item;
  final VoidCallback? onReview;

  const RentalHistoryCard({super.key, required this.item, this.onReview});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl?.trim();
    final fallback = Icon(
      item.iconData,
      color: AppColors.primaryColor,
      size: 28,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: item.itemId != null
                ? () => AppRoutes.openItemDetail(context, itemId: item.itemId!)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: imageUrl == null || imageUrl.isEmpty
                      ? fallback
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                ),
                const SizedBox(width: 16),
                // ── Details ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'เช่าจาก: ${item.ownerName}',
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: AppColors.labelColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (item.date.isNotEmpty) ...[
                            Text(
                              item.date,
                              style: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 11,
                                color: AppColors.hintTextColor,
                              ),
                            ),
                            const Text(
                              ' • ',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.hintTextColor,
                              ),
                            ),
                          ],
                          Text(
                            item.duration,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11,
                              color: AppColors.hintTextColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ── Status Badge ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: item.statusBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.status,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: item.statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (item.isCompleted) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF0EAF5)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFF59E0B),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.alreadyReviewed
                        ? 'รีวิวอุปกรณ์นี้แล้ว'
                        : 'คืนอุปกรณ์เรียบร้อยแล้ว',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: Color(0xFF5B5265),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!item.alreadyReviewed && onReview != null)
                  OutlinedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.rate_review_outlined, size: 16),
                    label: const Text('ให้คะแนน'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryColor,
                      side: const BorderSide(color: Color(0xFFE3D2F2)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
