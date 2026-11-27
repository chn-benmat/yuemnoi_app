import 'package:flutter/material.dart';

import '../../../../core/widgets/product_listing_card.dart';
import '../../domain/entities/feed_item.dart';

class ShopeeProductCard extends StatelessWidget {
  const ShopeeProductCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onFavoriteToggle,
  });

  final FeedItem item;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;

  @override
  Widget build(BuildContext context) => ProductListingCard(
    key: ValueKey('shopee-card-${item.id}'),
    title: item.title,
    imageUrl: item.imageUrl,
    price: item.price,
    locationName: item.locationName,
    paidBookingCount: item.paidBookingCount,
    isRentalOccupied: item.isRentalOccupied,
    onTap: onTap,
  );
}
