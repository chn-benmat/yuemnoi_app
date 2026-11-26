import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/widgets/skeleton_shimmer.dart';
import '../../domain/entities/feed_item.dart';

/// การ์ดแสดงสินค้าสไตล์ Shopee สำหรับ Grid 2 คอลัมน์ (ซ้าย-ขวา)
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
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('shopee-card-${item.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ส่วนภาพสินค้าอัตราส่วน 1:1 พร้อมป้าย Badge และปุ่มบันทึก
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        color: const Color(0xFFF3F4F6),
                        child: item.imageUrl.trim().isEmpty
                            ? _buildNoPictureThumbnail()
                            : item.imageUrl.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const SkeletonShimmer(
                                      child: ColoredBox(
                                        color: Color(0xFFE3E5E8),
                                      ),
                                    ),
                                errorWidget: (context, url, error) =>
                                    _buildNoPictureThumbnail(),
                              )
                            : Image.asset(
                                item.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildNoPictureThumbnail(),
                              ),
                      ),
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1E2226),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (item.isRentalOccupied) ...[
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'กำลังถูกเช่า',
                          style: TextStyle(
                            color: Color(0xFF315FA6),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '฿${_formatNumber(item.price)}',
                              style: const TextStyle(
                                color: AppColors.primaryColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (item.paidBookingCount > 0) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            flex: 3,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                'เช่าแล้ว ${_formatNumber(item.paidBookingCount)} ครั้ง',
                                style: const TextStyle(
                                  color: Color(0xFF7E848A),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Color(0xFF888E94),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            item.locationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF7E848A),
                              fontSize: 11,
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
      ),
    );
  }

  Widget _buildNoPictureThumbnail() {
    return Container(
      color: const Color(0xFFF3F4F6),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Color(0xFFADB5BD),
          size: 34,
        ),
      ),
    );
  }

  String _formatNumber(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
