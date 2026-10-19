import '../entities/feed_category.dart';
import '../entities/feed_item.dart';
import '../repositories/home_repository.dart';

/// ข้อมูลรวมสำหรับแสดงผลในหน้า Home Feed
class HomeFeedData {
  const HomeFeedData({
    required this.categories,
    required this.curatedItems,
    required this.nearbyItems,
  });

  final List<FeedCategory> categories;
  final List<FeedItem> curatedItems;
  final List<FeedItem> nearbyItems;
}

/// UseCase สำหรับดึงข้อมูลภาพรวมหน้า Home Feed
class GetHomeFeedUseCase {
  const GetHomeFeedUseCase(this.repository);

  final HomeRepository repository;

  Future<HomeFeedData> call({String? categoryId, String? searchQuery}) async {
    final categories = await repository.getCategories();
    final curatedItems = await repository.getCuratedItems();
    final nearbyItems = await repository.getNearbyItems(
      categoryId: categoryId,
      searchQuery: searchQuery,
    );

    return HomeFeedData(
      categories: categories,
      curatedItems: curatedItems,
      nearbyItems: nearbyItems,
    );
  }
}
