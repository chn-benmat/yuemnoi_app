import '../entities/item_detail.dart';
import '../entities/related_item.dart';
import '../repositories/related_items_repository.dart';

class GetRelatedItemsUseCase {
  const GetRelatedItemsUseCase(this.repository);
  final RelatedItemsRepository repository;

  Future<List<RelatedItem>> execute(ItemDetail item) async {
    final category = item.category.trim();
    if (category.isEmpty) return const [];
    final candidates = await repository.fetchByCategory(category);
    final seen = <int>{item.id};
    // API ค้นหมวดแบบบางส่วน จึงตรวจหมวดซ้ำก่อนแนะนำสินค้าที่ใช้แทนกันได้
    return candidates
        .where(
          (candidate) =>
              candidate.category.trim().toLowerCase() ==
                  category.toLowerCase() &&
              seen.add(candidate.id),
        )
        .take(6)
        .toList(growable: false);
  }
}
