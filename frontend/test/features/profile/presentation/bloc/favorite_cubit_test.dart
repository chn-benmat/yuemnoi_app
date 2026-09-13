import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/usecases/get_favorites_usecase.dart';
import 'package:frontend/features/profile/presentation/bloc/favorite_cubit.dart';
import 'package:frontend/features/profile/presentation/bloc/favorite_state.dart';

import '../../domain/usecases/user_items_usecases_test.dart';

void main() {
  group('FavoriteCubit', () {
    test('initial state is FavoriteInitial', () {
      final cubit = FavoriteCubit(
        getFavorites: GetFavoritesUseCase(FakeUserItemsRepository()),
      );
      expect(cubit.state, isA<FavoriteInitial>());
      cubit.close();
    });

    blocTest<FavoriteCubit, FavoriteState>(
      'loadFavorites emits [FavoriteLoading, FavoriteLoaded]',
      build: () => FavoriteCubit(
        getFavorites: GetFavoritesUseCase(FakeUserItemsRepository()),
      ),
      act: (cubit) => cubit.loadFavorites(),
      expect: () => [
        isA<FavoriteLoading>(),
        isA<FavoriteLoaded>().having((s) => s.items.length, 'items.length', 1),
      ],
    );
  });
}
