import '../../domain/entities/favorite_item.dart';

// คำอธิบาย: State สำหรับหน้ารายการอุปกรณ์ที่กดถูกใจ
abstract class FavoriteState {
  const FavoriteState();
}

class FavoriteInitial extends FavoriteState {
  const FavoriteInitial();
}

class FavoriteLoading extends FavoriteState {
  const FavoriteLoading();
}

class FavoriteLoaded extends FavoriteState {
  final List<FavoriteItem> items;
  const FavoriteLoaded(this.items);
}

class FavoriteError extends FavoriteState {
  final String message;
  const FavoriteError(this.message);
}
