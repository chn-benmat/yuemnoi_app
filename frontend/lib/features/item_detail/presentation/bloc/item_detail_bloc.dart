import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/item_catalog_service.dart';

import '../../domain/entities/item_detail.dart';
import '../../domain/repositories/item_detail_repository.dart';
import '../../domain/usecases/get_item_detail_usecase.dart';
import '../../domain/usecases/update_item_usecase.dart';
import '../../domain/usecases/manage_owner_item_usecase.dart';
import 'item_detail_event.dart';
import 'item_detail_state.dart';

class ItemDetailBloc extends Bloc<ItemDetailEvent, ItemDetailState> {
  ItemDetailBloc({
    required GetItemDetailUseCase getItem,
    required UpdateItemUseCase updateItem,
    ManageOwnerItemUseCase? manageItem,
    ItemDetail? initialItem,
  }) : _getItem = getItem,
       _updateItem = updateItem,
       _manageItem = manageItem,
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
    on<ItemVisibilityChanged>(_onVisibilityChanged);
    on<ItemDeleteSubmitted>(_onDeleteSubmitted);
  }

  final GetItemDetailUseCase _getItem;
  final UpdateItemUseCase _updateItem;
  final ManageOwnerItemUseCase? _manageItem;

  Future<void> _onRequested(
    ItemDetailRequested event,
    Emitter<ItemDetailState> emit,
  ) async {
    if (state.isBusy || state.status == ItemDetailStatus.deleted) return;
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
    if (state.isBusy || state.status == ItemDetailStatus.deleted) return;
    emit(state.copyWith(status: ItemDetailStatus.updating, clearError: true));
    try {
      final item = await _updateItem.execute(event.draft);
      ItemCatalogService.instance.notifyChanged();
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

  Future<void> _onVisibilityChanged(
    ItemVisibilityChanged event,
    Emitter<ItemDetailState> emit,
  ) async {
    final item = state.item;
    final manager = _manageItem;
    if (item == null ||
        manager == null ||
        state.isBusy ||
        state.status == ItemDetailStatus.deleted ||
        item.ownerHidden == event.hidden)
      return;
    emit(
      state.copyWith(
        status: ItemDetailStatus.changingVisibility,
        clearError: true,
      ),
    );
    try {
      final updated = await manager.setVisibility(item, hidden: event.hidden);
      ItemCatalogService.instance.notifyChanged();
      emit(
        state.copyWith(
          status: ItemDetailStatus.loaded,
          item: item.withVisibility(hidden: updated.ownerHidden),
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
          errorMessage: 'เปลี่ยนการแสดงอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่',
        ),
      );
    }
  }

  Future<void> _onDeleteSubmitted(
    ItemDeleteSubmitted event,
    Emitter<ItemDetailState> emit,
  ) async {
    final item = state.item;
    final manager = _manageItem;
    if (item == null ||
        manager == null ||
        state.isBusy ||
        state.status == ItemDetailStatus.deleted)
      return;
    emit(state.copyWith(status: ItemDetailStatus.deleting, clearError: true));
    try {
      await manager.delete(item);
      ItemCatalogService.instance.notifyChanged();
      emit(state.copyWith(status: ItemDetailStatus.deleted, clearError: true));
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
          errorMessage: 'ลบอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่',
        ),
      );
    }
  }
}
