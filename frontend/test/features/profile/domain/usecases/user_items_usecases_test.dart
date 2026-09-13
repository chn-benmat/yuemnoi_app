import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/entities/favorite_item.dart';
import 'package:frontend/features/profile/domain/entities/user_item.dart';
import 'package:frontend/features/profile/domain/repositories/user_items_repository.dart';
import 'package:frontend/features/profile/domain/usecases/get_favorites_usecase.dart';
import 'package:frontend/features/profile/domain/usecases/get_my_items_usecase.dart';

class FakeUserItemsRepository implements UserItemsRepository {
  List<UserItem> items = [
    const UserItem(
      id: 1,
      title: 'Item 1',
      subtitle: 'Sub 1',
      price: 100,
      category: 'กล้อง',
    ),
  ];

  List<FavoriteItem> favorites = [
    const FavoriteItem(
      id: 2,
      title: 'Fav 1',
      ownerId: 'owner_1',
      ownerName: 'Owner One',
      price: 200,
      category: 'โดรน',
    ),
  ];

  @override
  Future<List<UserItem>> getMyItems(String userId) async {
    return items;
  }

  @override
  Future<List<FavoriteItem>> getFavorites() async {
    return favorites;
  }
}

void main() {
  late FakeUserItemsRepository repository;

  setUp(() {
    repository = FakeUserItemsRepository();
  });

  test('GetMyItemsUseCase returns user items', () async {
    final useCase = GetMyItemsUseCase(repository);
    final result = await useCase.execute('u1');

    expect(result.length, 1);
    expect(result.first.title, 'Item 1');
    expect(result.first.price, 100);
  });

  test('GetFavoritesUseCase returns favorite items', () async {
    final useCase = GetFavoritesUseCase(repository);
    final result = await useCase.execute();

    expect(result.length, 1);
    expect(result.first.title, 'Fav 1');
    expect(result.first.ownerName, 'Owner One');
  });
}
