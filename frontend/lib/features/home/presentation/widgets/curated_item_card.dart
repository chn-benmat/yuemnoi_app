import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/feed_item.dart';

/// การ์ดแสดงอุปกรณ์คัดสรรประจำวัน (Curated Daily Item Card)
class CuratedItemCard extends StatelessWidget {
  const CuratedItemCard({
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
      width: 230,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFF1F3F5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('curated-card-${item.id}'),
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ส่วนรูปภาพพร้อมป้ายราคาและปุ่ม Favorite
                Stack(
                  children: [
                    // กล่องรูปภาพอุปกรณ์
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        height: 190,
                        width: double.infinity,
                        color: const Color(0xFFF6F7F9),
                        child: item.imageUrl.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: const Color(0xFFEFF1F4),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primaryColor,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    _buildFallbackImage(),
                              )
                            : Image.asset(
                                item.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildFallbackImage(),
                              ),
                      ),
                    ),

                    // ป้ายราคาลอยขวาบน
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_formatPrice(item.price)} ฿',
                              style: const TextStyle(
                                color: Color(0xFF1E2022),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              ' ${item.priceUnit}',
                              style: const TextStyle(
                                color: Color(0xFF6B7075),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ชื่ออุปกรณ์และคะแนนรีวิวดาว
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1E2022),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // คะแนนรีวิว
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF5FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: AppColors.primaryColor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ข้อมูลเจ้าของอุปกรณ์
                Row(
                  children: [
                    // รูปโปรไฟล์เจ้าของ
                    _buildOwnerAvatar(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF55595C),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerAvatar() {
    if (item.ownerAvatarUrl != null && item.ownerAvatarUrl!.isNotEmpty) {
      if (item.ownerAvatarUrl!.startsWith('http')) {
        return CircleAvatar(
          radius: 12,
          backgroundImage: CachedNetworkImageProvider(item.ownerAvatarUrl!),
        );
      } else {
        return CircleAvatar(
          radius: 12,
          backgroundImage: AssetImage(item.ownerAvatarUrl!),
        );
      }
    }
    return CircleAvatar(
      radius: 12,
      backgroundColor: AppColors.primaryColor.withValues(alpha: 0.15),
      child: Text(
        item.ownerName.isNotEmpty ? item.ownerName[0] : 'U',
        style: const TextStyle(
          color: AppColors.primaryColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFallbackImage() {
    return Container(
      color: const Color(0xFFF1F3F6),
      child: const Center(
        child: Icon(
          Icons.photo_camera_back_outlined,
          color: Color(0xFFBAC0C5),
          size: 44,
        ),
      ),
    );
  }

  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
