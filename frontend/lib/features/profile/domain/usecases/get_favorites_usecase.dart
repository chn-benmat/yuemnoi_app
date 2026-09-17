import '../entities/favorite_item.dart';
import '../repositories/user_items_repository.dart';

// คำอธิบาย: UseCase สำหรับดึงรายการอุปกรณ์ที่ผู้ใช้กดถูกใจไว้ (Favorites)
class GetFavoritesUseCase {
  final UserItemsRepository repository;

  const GetFavoritesUseCase(this.repository);

  Future<List<FavoriteItem>> execute() {
    return repository.getFavorites();
  }
}
