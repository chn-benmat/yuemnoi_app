import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/rental_booking.dart';

class RentalHistoryLoadingSkeleton extends StatelessWidget {
  const RentalHistoryLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      key: const ValueKey('rental-history-loading-skeleton'),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 56, height: 56, borderRadius: 14),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 16, borderRadius: 8),
                SizedBox(height: 7),
                FractionallySizedBox(
                  widthFactor: 0.72,
                  child: SkeletonBox(height: 12, borderRadius: 6),
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: SkeletonBox(height: 10, borderRadius: 5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 52, height: 22, borderRadius: 8),
        ],
      ),
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class RentalHistoryItemData {
  final int? itemId;
  final String title;
  final String ownerName;
  final String duration;
  final String date;
  final String status;
  final Color statusColor;
  final Color statusBgColor;
  final IconData iconData;

  RentalHistoryItemData({
    this.itemId,
    required this.title,
    required this.ownerName,
    required this.duration,
    required this.date,
    required this.status,
    required this.statusColor,
    required this.statusBgColor,
    required this.iconData,
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
      itemId: entity.itemId,
      title: entity.title,
      ownerName: entity.partnerName,
      duration: entity.duration,
      date: dateStr,
      status: entity.status,
      statusColor: statusColor,
      statusBgColor: statusBgColor,
      iconData: iconData,
    );
  }
}

// ─── Card Widget ──────────────────────────────────────────────────────────────

class RentalHistoryCard extends StatelessWidget {
  final RentalHistoryItemData item;

  const RentalHistoryCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.itemId != null
          ? () => AppRoutes.openItemDetail(context, itemId: item.itemId!)
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon Box ──
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                item.iconData,
                color: AppColors.primaryColor,
                size: 28,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    );
  }
}
