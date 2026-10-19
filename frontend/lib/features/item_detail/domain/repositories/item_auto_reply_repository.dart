import '../entities/item_auto_reply.dart';

abstract interface class ItemAutoReplyRepository {
  Future<ItemAutoReply> load(int itemId);
  Future<ItemAutoReply> save(int itemId, ItemAutoReply settings);
}
