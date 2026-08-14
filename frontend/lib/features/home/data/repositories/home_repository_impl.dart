import '../../domain/entities/feed_category.dart';
import '../../domain/entities/feed_item.dart';
import '../../domain/repositories/home_repository.dart';
import '../datasources/home_supabase_data_source.dart';

/// การนำสัญญา HomeRepository ไปใช้งานจริง ดึงข้อมูลจริงจาก Supabase
class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({HomeSupabaseDataSource? dataSource})
      : _dataSource = dataSource ?? HomeSupabaseDataSource();

  final HomeSupabaseDataSource _dataSource;

  @override
  Future<List<FeedCategory>> getCategories() async {
    final categories = await _dataSource.fetchCategories();
    return categories.map((c) => c.toEntity()).toList();
  }

  @override
  Future<List<FeedItem>> getCuratedItems() async {
    final items = await _dataSource.fetchCuratedItems();
    return items.map((i) => i.toEntity()).toList();
  }

  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async {
    final items = await _dataSource.fetchNearbyItems(
      categoryId: categoryId,
      searchQuery: searchQuery,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minRating: minRating,
    );
    return items.map((i) => i.toEntity()).toList();
  }

  @override
  Future<bool> toggleFavorite(String itemId) async {
    return _dataSource.toggleFavorite(itemId);
  }
}

