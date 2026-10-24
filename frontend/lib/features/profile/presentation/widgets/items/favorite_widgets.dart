import 'package:flutter/material.dart';

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
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent:
              270 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 4,
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
    return Material(
      color: const Color(0xFFF0E6FF),
      elevation: 1,
      shadowColor: const Color(0x267C3AED),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFD8BFF0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => AppRoutes.openItemDetail(context, itemId: item.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: const Color(0xFFE8D9FA),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child:
                          item.imageUrl != null &&
                              item.imageUrl!.trim().isNotEmpty
                          ? Image.network(
                              item.imageUrl!.trim(),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.image_not_supported_outlined,
                                    color: Color(0xFF9485A8),
                                    size: 36,
                                  ),
                            )
                          : const Icon(
                              Icons.devices_other_outlined,
                              color: Color(0xFF9485A8),
                              size: 36,
                            ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton.filled(
                      tooltip: 'นำออกจากรายการโปรด',
                      onPressed: onRemoveFavorite,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFE44875),
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.favorite_rounded, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF201A2D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront_outlined,
                        size: 14,
                        color: Color(0xFF82798E),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11,
                            color: Color(0xFF71677E),
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
