import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/item_detail.dart';
import '../../domain/repositories/item_detail_repository.dart';
import '../../domain/usecases/get_item_detail_usecase.dart';
import '../../domain/usecases/update_item_usecase.dart';
import 'item_detail_event.dart';
import 'item_detail_state.dart';

class ItemDetailBloc extends Bloc<ItemDetailEvent, ItemDetailState> {
  ItemDetailBloc({
    required GetItemDetailUseCase getItem,
    required UpdateItemUseCase updateItem,
    ItemDetail? initialItem,
  }) : _getItem = getItem,
       _updateItem = updateItem,
       super(
         ItemDetailState(
           status: initialItem == null
               ? ItemDetailStatus.initial
               : ItemDetailStatus.loaded,
           item: initialItem,
         ),
       ) {
    on<ItemDetailRequested>(_onRequested);
    on<ItemDetailUpdateSubmitted>(_onUpdateSubmitted);
  }

  final GetItemDetailUseCase _getItem;
  final UpdateItemUseCase _updateItem;

  Future<void> _onRequested(
    ItemDetailRequested event,
    Emitter<ItemDetailState> emit,
  ) async {
    emit(state.copyWith(status: ItemDetailStatus.loading, clearError: true));
    try {
      final item = await _getItem.execute(event.itemId);
      emit(
        state.copyWith(
          status: ItemDetailStatus.loaded,
          item: item,
          clearError: true,
        ),
      );
    } on ItemDetailException catch (error) {
      emit(
        state.copyWith(
          status: ItemDetailStatus.failure,
          errorMessage: error.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ItemDetailStatus.failure,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่',
        ),
      );
    }
  }

  Future<void> _onUpdateSubmitted(
    ItemDetailUpdateSubmitted event,
    Emitter<ItemDetailState> emit,
  ) async {
    if (state.status == ItemDetailStatus.updating) return;
    emit(state.copyWith(status: ItemDetailStatus.updating, clearError: true));
    try {
      final item = await _updateItem.execute(event.draft);
      emit(
        state.copyWith(
          status: ItemDetailStatus.loaded,
          item: item,
          clearError: true,
        ),
      );
    } on ItemDetailException catch (error) {
      emit(
        state.copyWith(
          status: ItemDetailStatus.failure,
          errorMessage: error.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ItemDetailStatus.failure,
          errorMessage: 'เกิดข้อผิดพลาด กรุณาลองใหม่',
        ),
      );
    }
  }
}
