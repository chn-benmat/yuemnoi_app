import 'package:flutter/material.dart';

import '../../domain/entities/feed_item.dart';
import 'home_empty_state.dart';
import 'nearby_item_card.dart';

/// ส่วนแสดงรายการอุปกรณ์ให้เช่าในบริเวณใกล้เคียง
class NearbyItemsSection extends StatelessWidget {
  const NearbyItemsSection({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onFavoriteToggle,
    this.searchQuery = '',
  });

  final List<FeedItem> items;
  final ValueChanged<FeedItem> onItemTap;
  final ValueChanged<FeedItem> onFavoriteToggle;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ส่วนหัวข้อ "ใกล้ฉัน" และ "อุปกรณ์ให้เช่า ใกล้ฉัน"
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ใกล้ฉัน',
                style: TextStyle(
                  color: Color(0xFF6E7276),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'อุปกรณ์ให้เช่า\nใกล้ฉัน',
                    style: TextStyle(
                      color: Color(0xFF1B1E21),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  if (items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${items.length} รายการ',
                        style: const TextStyle(
                          color: Color(0xFF5E6266),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // รายการสินค้า หรือ Empty State
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: HomeEmptyState(searchQuery: searchQuery),
          )
        else
          ListView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return NearbyItemCard(
                item: item,
                onTap: () => onItemTap(item),
                onFavoriteToggle: () => onFavoriteToggle(item),
              );
            },
          ),
      ],
    );
  }
}
