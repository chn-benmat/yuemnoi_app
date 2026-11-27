import '../entities/user_item.dart';
import '../repositories/user_items_repository.dart';

// คำอธิบาย: UseCase สำหรับดึงรายการอุปกรณ์ที่ผู้ใช้ลงปล่อยเช่าไว้
class GetMyItemsUseCase {
  final UserItemsRepository repository;

  const GetMyItemsUseCase(this.repository);

  Future<List<UserItem>> execute(String userId) {
    return repository.getMyItems(userId);
  }

  Stream<void> watchChanges(String userId) =>
      repository.watchMyItemChanges(userId);
}
