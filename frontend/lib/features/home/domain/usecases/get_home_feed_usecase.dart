import 'dart:async';

import '../entities/feed_category.dart';
import '../entities/feed_item.dart';
import '../repositories/home_repository.dart';

/// ข้อมูลรวมสำหรับแสดงผลในหน้า Home Feed
class HomeFeedData {
  const HomeFeedData({
    required this.categories,
    required this.curatedItems,
    required this.nearbyItems,
    this.hasRankedOrder = false,
    this.nextCursor,
  });

  final List<FeedCategory> categories;
  final List<FeedItem> curatedItems;
  final List<FeedItem> nearbyItems;
  final bool hasRankedOrder;
  final String? nextCursor;
}

/// UseCase สำหรับดึงข้อมูลภาพรวมหน้า Home Feed
class GetHomeFeedUseCase {
  const GetHomeFeedUseCase(this.repository);

  final HomeRepository repository;

  RankedHomeFeedRepository? get _rankedRepository => switch (repository) {
    final RankedHomeFeedRepository ranked => ranked,
    _ => null,
  };

  bool get supportsRankedFeed => _rankedRepository != null;

  Future<RankedHomePage?> getRankedPage({
    double? latitude,
    double? longitude,
    List<String> recentCategories = const [],
    String? cursor,
  }) async => _rankedRepository?.getRankedItems(
    latitude: latitude,
    longitude: longitude,
    recentCategories: recentCategories,
    cursor: cursor,
  );

  Future<HomeFeedData> call({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
    double? latitude,
    double? longitude,
    List<String> recentCategories = const [],
    List<FeedItem>? previousRankedItems,
  }) async {
    final isDefault =
        (categoryId == null || categoryId == 'all') &&
        (searchQuery == null || searchQuery.trim().isEmpty) &&
        minPrice == null &&
        maxPrice == null &&
        minRating == null;

    // เริ่มคำขอฟีดก่อนรอหมวดหมู่ เพื่อให้คำขอใช้บัญชีที่เริ่มโหลดฟีด
    final (categories, firstPage) = await (
      repository.getCategories(),
      isDefault
          ? getRankedPage(
              latitude: latitude,
              longitude: longitude,
              recentCategories: recentCategories,
            )
          : Future<RankedHomePage?>.value(),
    ).wait;
    if (isDefault && supportsRankedFeed) {
      if (firstPage != null) {
        final seen = <String>{};
        return HomeFeedData(
          categories: categories,
          curatedItems: const [],
          nearbyItems: firstPage.items
              .where((item) => seen.add(item.id))
              .toList(),
          hasRankedOrder: true,
          nextCursor: firstPage.nextCursor,
        );
      }
      if (previousRankedItems != null) {
        return HomeFeedData(
          categories: categories,
          curatedItems: const [],
          nearbyItems: previousRankedItems,
          hasRankedOrder: true,
        );
      }
    }

    final curatedItems = await repository.getCuratedItems();
    final nearbyItems = await repository.getNearbyItems(
      categoryId: categoryId,
      searchQuery: searchQuery,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minRating: minRating,
    );
    return HomeFeedData(
      categories: categories,
      curatedItems: curatedItems,
      nearbyItems: nearbyItems,
    );
  }
}
