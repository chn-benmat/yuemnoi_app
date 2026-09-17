import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/skeleton_shimmer.dart';
import '../../../domain/entities/favorite_item.dart';

class FavoriteLoadingSkeleton extends StatelessWidget {
  const FavoriteLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      key: const ValueKey('favorite-loading-skeleton'),
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => const _FavoriteSkeletonCard(),
      ),
    );
  }
}

class _FavoriteSkeletonCard extends StatelessWidget {
  const _FavoriteSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: SkeletonBox(height: double.infinity, borderRadius: 12),
          ),
          const SizedBox(height: 8),
          const SkeletonBox(height: 14, borderRadius: 7),
          const SizedBox(height: 6),
          const FractionallySizedBox(
            widthFactor: 0.7,
            child: SkeletonBox(height: 10, borderRadius: 5),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ─── Favorite Item Data ───────────────────────────────────────────────────────

class FavoriteItemData {
  final int id;
  final String title;
  final String ownerId;
  String ownerName;
  final String? imageUrl;
  final double price;
  final String category;

  FavoriteItemData({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.ownerName,
    this.imageUrl,
    this.price = 0.0,
    this.category = '',
  });

  factory FavoriteItemData.fromEntity(FavoriteItem entity) {
    return FavoriteItemData(
      id: entity.id,
      title: entity.title,
      ownerId: entity.ownerId,
      ownerName: entity.ownerName,
      imageUrl: entity.imageUrl,
      price: entity.price,
      category: entity.category,
    );
  }
}

// ─── Favorite Card ────────────────────────────────────────────────────────────

class FavoriteItemCard extends StatelessWidget {
  final FavoriteItemData item;
  final VoidCallback onRemoveFavorite;

  const FavoriteItemCard({
    super.key,
    required this.item,
    required this.onRemoveFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AppRoutes.openItemDetail(context, itemId: item.id),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image ──
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child:
                        item.imageUrl != null &&
                            item.imageUrl!.trim().isNotEmpty
                        ? Image.network(
                            item.imageUrl!.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color: const Color(0xFF2E1065),
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                    color: Colors.white54,
                                    size: 36,
                                  ),
                                ),
                          )
                        : Container(
                            color: const Color(0xFF2E1065),
                            child: const Icon(
                              Icons.devices_other_outlined,
                              color: Colors.white54,
                              size: 36,
                            ),
                          ),
                  ),
                  // Heart button to remove
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: onRemoveFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Color(0xFFFF3B5F),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Text Details ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'เจ้าของ: ${item.ownerName}',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
