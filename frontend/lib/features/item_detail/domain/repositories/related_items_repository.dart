import '../entities/related_item.dart';

class RelatedItemsException implements Exception {
  const RelatedItemsException(this.message);
  final String message;
}

abstract interface class RelatedItemsRepository {
  Future<List<RelatedItem>> fetchByCategory(String category);
}
