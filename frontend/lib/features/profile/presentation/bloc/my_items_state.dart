import '../../domain/entities/user_item.dart';

// คำอธิบาย: State สำหรับหน้าจัดการอุปกรณ์ของฉัน (My Items)
abstract class MyItemsState {
  const MyItemsState();
}

class MyItemsInitial extends MyItemsState {
  const MyItemsInitial();
}

class MyItemsLoading extends MyItemsState {
  const MyItemsLoading();
}

class MyItemsLoaded extends MyItemsState {
  final List<UserItem> items;
  const MyItemsLoaded(this.items);
}

class MyItemsError extends MyItemsState {
  final String message;
  const MyItemsError(this.message);
}
