import '../entities/feed_category.dart';
import '../entities/feed_item.dart';

/// สัญญาของ Repository สำหรับดึงและจัดการข้อมูลหน้า Home Feed
abstract class HomeRepository {
  /// ดึงรายการหมวดหมู่ทั้งหมด
  Future<List<FeedCategory>> getCategories();

  /// ดึงรายการอุปกรณ์คัดสรรประจำวัน (Curated Daily)
  Future<List<FeedItem>> getCuratedItems();

  /// ดึงรายการอุปกรณ์ใกล้เคียง พร้อมรองรับการกรองตามหมวดหมู่ ค้นหา ราคา และคะแนนรีวิว
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  });

  /// สลับสถานะรายการโปรดของอุปกรณ์
  Future<bool> toggleFavorite(String itemId);

  /// ล้างแคชในหน่วยความจำเพื่อบังคับโหลดข้อมูลใหม่
  void clearCache({bool rotateRecommendations = true}) {}
}

typedef RankedHomePage = ({List<FeedItem> items, String? nextCursor});

class RankedHomeCursorInvalid implements Exception {
  const RankedHomeCursorInvalid();
}

abstract interface class RankedHomeFeedRepository {
  Future<RankedHomePage?> getRankedItems({
    double? latitude,
    double? longitude,
    List<String> recentCategories = const [],
    String? cursor,
  });
}
