import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/user_item.dart';

// ─────────────────────────────────────────────────────────────────────────────

class MyItemData {
  final int? id;
  final String title;
  final String subtitle;
  final double price;
  final int imageCount;
  final String? imageUrl;
  final IconData iconData;

  const MyItemData({
    this.id,
    required this.title,
    required this.subtitle,
    this.price = 0.0,
    required this.imageCount,
    this.imageUrl,
    required this.iconData,
  });

  factory MyItemData.fromEntity(UserItem entity, IconData icon) {
    return MyItemData(
      id: entity.id,
      title: entity.title,
      subtitle: entity.subtitle,
      price: entity.price,
      imageCount: entity.imageCount,
      imageUrl: entity.imageUrl,
      iconData: icon,
    );
  }
}

class MyItemsLoadingSkeleton extends StatelessWidget {
  const MyItemsLoadingSkeleton({super.key});

  static const _placeholderCount = 5;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      key: const ValueKey('my-items-skeleton'),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _placeholderCount,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => const _MyItemSkeletonCard(),
      ),
    );
  }
}

class _MyItemSkeletonCard extends StatelessWidget {
  const _MyItemSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 80, height: 86, borderRadius: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FractionallySizedBox(
                    widthFactor: 0.62,
                    child: SkeletonBox(height: 14, borderRadius: 6),
                  ),
                  const SizedBox(height: 7),
                  const FractionallySizedBox(
                    widthFactor: 0.82,
                    child: SkeletonBox(height: 10, borderRadius: 5),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const SkeletonBox(width: 48, height: 12, borderRadius: 6),
                      const SizedBox(width: 8),
                      const SkeletonBox(width: 64, height: 12, borderRadius: 6),
                      const Spacer(),
                      SkeletonBox(width: 14, height: 14, borderRadius: 7),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MyItemCard extends StatelessWidget {
  final MyItemData item;
  const MyItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (item.id != null) {
          AppRoutes.openItemDetail(context, itemId: item.id!);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Thumbnail ─────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              child: Container(
                width: 80,
                height: 86,
                color: const Color(0xFFF3E8FF),
                child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, st) => Icon(
                          item.iconData,
                          color: AppColors.primaryColor,
                          size: 32,
                        ),
                      )
                    : Icon(
                        item.iconData,
                        color: AppColors.primaryColor,
                        size: 32,
                      ),
              ),
            ),

            // ── Info ──────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        color: AppColors.labelColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        MyItemActionChip(
                          icon: Icons.photo_library_outlined,
                          label: '${item.imageCount} รูป',
                        ),
                        if (item.price > 0) ...[
                          const SizedBox(width: 8),
                          MyItemActionChip(
                            icon: Icons.monetization_on_outlined,
                            label: '${item.price.toInt()} ฿/วัน',
                          ),
                        ],
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            if (item.id != null) {
                              AppRoutes.openItemDetail(
                                context,
                                itemId: item.id!,
                              );
                            }
                          },
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: AppColors.hintTextColor,
                          ),
                        ),
                      ],
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

class MyItemActionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const MyItemActionChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.fieldIconColor),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10,
            color: AppColors.labelColor,
          ),
        ),
      ],
    );
  }
}
