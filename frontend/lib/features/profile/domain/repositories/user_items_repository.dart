import '../entities/favorite_item.dart';
import '../entities/user_item.dart';

// คำอธิบาย: สัญญาการทำงานของ UserItemsRepository ในชั้น Domain
abstract class UserItemsRepository {
  Future<List<UserItem>> getMyItems(String userId);
  Future<List<FavoriteItem>> getFavorites();
}
