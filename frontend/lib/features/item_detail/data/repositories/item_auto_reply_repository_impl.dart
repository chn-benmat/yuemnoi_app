import '../../domain/entities/item_auto_reply.dart';
import '../../domain/repositories/item_auto_reply_repository.dart';
import '../datasources/item_auto_reply_remote_data_source.dart';

class ItemAutoReplyRepositoryImpl implements ItemAutoReplyRepository {
  const ItemAutoReplyRepositoryImpl(this.remote);
  final ItemAutoReplyRemoteDataSource remote;

  @override
  Future<ItemAutoReply> load(int itemId) => remote.load(itemId);
  @override
  Future<ItemAutoReply> save(int itemId, ItemAutoReply settings) =>
      remote.save(itemId, settings);
}
