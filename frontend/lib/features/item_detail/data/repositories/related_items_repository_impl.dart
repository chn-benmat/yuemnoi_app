import '../../domain/entities/related_item.dart';
import '../../domain/repositories/related_items_repository.dart';
import '../datasources/related_items_remote_data_source.dart';
import '../models/related_item_model.dart';

class RelatedItemsRepositoryImpl implements RelatedItemsRepository {
  const RelatedItemsRepositoryImpl(this.remoteDataSource);
  final RelatedItemsRemoteDataSource remoteDataSource;

  @override
  Future<List<RelatedItem>> fetchByCategory(String category) async {
    final rows = await remoteDataSource.fetchByCategory(category);
    final items = <RelatedItem>[];
    for (final row in rows) {
      if (row['owner_hidden'] == true) continue;
      try {
        items.add(RelatedItemModel.fromJson(row));
      } on FormatException {
        // ข้ามแถวที่ข้อมูลไม่ครบ แทนการสร้างชื่อหรือราคาจำลอง
      }
    }
    return items;
  }
}
