import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/user_items_repository_impl.dart';
import '../../domain/usecases/get_my_items_usecase.dart';
import 'my_items_state.dart';

// คำอธิบาย: Cubit สำหรับจัดการสถานะการโหลดอุปกรณ์ของผู้ใช้
class MyItemsCubit extends Cubit<MyItemsState> {
  final GetMyItemsUseCase getMyItems;

  MyItemsCubit({GetMyItemsUseCase? getMyItems})
      : getMyItems = getMyItems ?? GetMyItemsUseCase(UserItemsRepositoryImpl()),
        super(const MyItemsInitial());

  Future<void> loadMyItems(String userId) async {
    emit(const MyItemsLoading());
    try {
      final items = await getMyItems.execute(userId);
      emit(MyItemsLoaded(items));
    } catch (e) {
      emit(MyItemsError(e.toString()));
    }
  }
}
