import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../domain/entities/feed_item.dart';
import 'curated_item_card.dart';

/// ส่วนแสดงรายการอุปกรณ์คัดสรรประจำวัน "สำหรับคุณ"
class CuratedDailySection extends StatelessWidget {
  const CuratedDailySection({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onFavoriteToggle,
    this.onViewAllTap,
  });

  final List<FeedItem> items;
  final ValueChanged<FeedItem> onItemTap;
  final ValueChanged<FeedItem> onFavoriteToggle;
  final VoidCallback? onViewAllTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ส่วนหัวของ Section: CURATED DAILY / สำหรับคุณ / ทั้งหมด
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CURATED DAILY',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'สำหรับคุณ',
                    style: TextStyle(
                      color: Color(0xFF1B1E21),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // ปุ่มดูทั้งหมด
              InkWell(
                onTap: onViewAllTap,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'ทั้งหมด',
                        style: TextStyle(
                          color: AppColors.primaryColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.primaryColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // รายการการ์ดเลื่อนแนวนอน
        SizedBox(
          height: 300,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final item = items[index];
              return CuratedItemCard(
                item: item,
                onTap: () => onItemTap(item),
                onFavoriteToggle: () => onFavoriteToggle(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
