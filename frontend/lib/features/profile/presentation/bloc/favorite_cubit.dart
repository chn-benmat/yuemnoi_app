import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/user_items_repository_impl.dart';
import '../../domain/usecases/get_favorites_usecase.dart';
import 'favorite_state.dart';

// คำอธิบาย: Cubit สำหรับจัดการสถานะของรายการที่กดถูกใจ
class FavoriteCubit extends Cubit<FavoriteState> {
  final GetFavoritesUseCase getFavorites;

  FavoriteCubit({GetFavoritesUseCase? getFavorites})
      : getFavorites = getFavorites ?? GetFavoritesUseCase(UserItemsRepositoryImpl()),
        super(const FavoriteInitial());

  Future<void> loadFavorites() async {
    emit(const FavoriteLoading());
    try {
      final items = await getFavorites.execute();
      emit(FavoriteLoaded(items));
    } catch (e) {
      emit(FavoriteError(e.toString()));
    }
  }
}
