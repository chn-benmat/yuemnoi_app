import '../../domain/entities/favorite_item.dart';
import '../../domain/entities/user_item.dart';
import '../../domain/repositories/user_items_repository.dart';
import '../datasources/user_items_remote_data_source.dart';

// คำอธิบาย: Implementation ของ UserItemsRepository ในชั้น Data
class UserItemsRepositoryImpl implements UserItemsRepository {
  final UserItemsRemoteDataSource remoteDataSource;

  UserItemsRepositoryImpl({UserItemsRemoteDataSource? remoteDataSource})
      : remoteDataSource = remoteDataSource ?? UserItemsRemoteDataSource();

  @override
  Future<List<UserItem>> getMyItems(String userId) async {
    final models = await remoteDataSource.getMyItems(userId);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<FavoriteItem>> getFavorites() async {
    final models = await remoteDataSource.getFavorites();
    return models.map((m) => m.toEntity()).toList();
  }
}
