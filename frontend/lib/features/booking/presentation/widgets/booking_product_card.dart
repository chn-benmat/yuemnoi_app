import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/services/item_review_service.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';

class BookingProductCard extends StatefulWidget {
  const BookingProductCard({super.key, required this.item});

  final BookingItemInfo item;

  @override
  State<BookingProductCard> createState() => _BookingProductCardState();
}

class _BookingProductCardState extends State<BookingProductCard> {
  late double _rating;
  late int _reviewCount;

  @override
  void initState() {
    super.initState();
    _rating = widget.item.rating;
    _reviewCount = widget.item.reviewCount;
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant BookingProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _rating = widget.item.rating;
      _reviewCount = widget.item.reviewCount;
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    if (widget.item.id <= 0) return;
    try {
      final stats = await ItemReviewService.fetchStats(widget.item.id);
      if (mounted) {
        setState(() {
          _rating = stats.rating;
          _reviewCount = stats.reviewCount;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasReviews = _reviewCount > 0 && _rating > 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // รูปภาพอุปกรณ์
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: widget.item.imageUrl.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: widget.item.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.photo_camera_back_rounded,
                        color: Color(0xFF9E9E9E),
                        size: 36,
                      ),
                    )
                  : Image.asset(
                      widget.item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.photo_camera_back_rounded,
                        color: Color(0xFF9E9E9E),
                        size: 36,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // ข้อมูลชื่อและคะแนนรีวิว
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'สินค้าที่คุณเลือก',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11,
                    color: AppColors.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.item.title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2022),
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      hasReviews
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 18,
                      color: hasReviews
                          ? const Color(0xFFFFB800)
                          : const Color(0xFF9E9E9E),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        hasReviews
                            ? '${_rating.toStringAsFixed(1)} ($_reviewCount รีวิว)'
                            : 'ยังไม่มีรีวิว',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          color: hasReviews
                              ? const Color(0xFF757778)
                              : const Color(0xFF9E9E9E),
                          fontWeight: hasReviews
                              ? FontWeight.w500
                              : FontWeight.w400,
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
    );
  }
}
