import 'package:flutter/foundation.dart';

import '../network/supabase_client.dart';

class ItemReviewStats {
  final double rating;
  final int reviewCount;

  const ItemReviewStats({
    required this.rating,
    required this.reviewCount,
  });

  static const empty = ItemReviewStats(rating: 0.0, reviewCount: 0);

  bool get hasReviews => reviewCount > 0 && rating > 0.0;
}

class ItemReviewService {
  ItemReviewService._();

  /// ดึงข้อมูลคะแนนเฉลี่ยและจำนวนรีวิวจริงของอุปกรณ์จากตาราง review_tb ใน Supabase
  static Future<ItemReviewStats> fetchStats(int itemId) async {
    if (itemId <= 0) return ItemReviewStats.empty;

    try {
      if (!SupabaseConfig.isInitialized) {
        return ItemReviewStats.empty;
      }

      final client = SupabaseConfig.client;
      final response = await client
          .from('review_tb')
          .select('rating')
          .eq('item_id', itemId);

      final reviews = response as List<dynamic>;
      if (reviews.isEmpty) {
        return ItemReviewStats.empty;
      }

      double sum = 0.0;
      int count = 0;
      for (final item in reviews) {
        if (item is Map<String, dynamic>) {
          final rawRating = item['rating'];
          final parsed = rawRating is num
              ? rawRating.toDouble()
              : double.tryParse('$rawRating');
          if (parsed != null && parsed >= 1.0 && parsed <= 5.0) {
            sum += parsed;
            count++;
          }
        }
      }

      if (count == 0) return ItemReviewStats.empty;

      final average = double.parse((sum / count).toStringAsFixed(1));
      return ItemReviewStats(
        rating: average,
        reviewCount: count,
      );
    } catch (e) {
      debugPrint('Error fetching review stats for item $itemId: $e');
      return ItemReviewStats.empty;
    }
  }
}
