import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/user_items_repository_impl.dart';
import '../../domain/entities/user_item.dart';
import '../../domain/usecases/get_my_items_usecase.dart';
import 'my_items_state.dart';

// คำอธิบาย: Cubit สำหรับจัดการสถานะการโหลดอุปกรณ์ของผู้ใช้
class MyItemsCubit extends Cubit<MyItemsState> {
  final GetMyItemsUseCase getMyItems;
  String _query = '';
  MyItemsFilter? _statusFilter;
  int _requestId = 0;

  MyItemsCubit({GetMyItemsUseCase? getMyItems})
    : getMyItems = getMyItems ?? GetMyItemsUseCase(UserItemsRepositoryImpl()),
      super(const MyItemsInitial());

  Future<void> loadMyItems(String userId) async {
    final requestId = ++_requestId;
    final previous = state;
    if (previous is MyItemsLoaded) {
      _emitLoaded(previous.items, isRefreshing: true);
    } else {
      emit(MyItemsLoading(query: _query, statusFilter: _statusFilter));
    }
    try {
      final items = await getMyItems.execute(userId);
      if (isClosed || requestId != _requestId) return;
      _emitLoaded(List.unmodifiable(items));
    } catch (e) {
      if (isClosed || requestId != _requestId) return;
      if (previous is MyItemsLoaded) {
        _emitLoaded(previous.items, refreshError: e.toString());
      } else {
        emit(
          MyItemsError(
            e.toString(),
            query: _query,
            statusFilter: _statusFilter,
          ),
        );
      }
    }
  }

  void search(String query) {
    _query = query;
    _updateSelection();
  }

  void filterByStatus(MyItemsFilter? status) {
    _statusFilter = status;
    _updateSelection();
  }

  void clearFilters() {
    _query = '';
    _statusFilter = null;
    _updateSelection();
  }

  void _updateSelection() {
    final current = state;
    if (current is MyItemsLoaded) {
      _emitLoaded(
        current.items,
        isRefreshing: current.isRefreshing,
        refreshError: current.refreshError,
      );
    } else if (current is MyItemsError) {
      emit(
        MyItemsError(
          current.message,
          query: _query,
          statusFilter: _statusFilter,
        ),
      );
    } else {
      // ช่องค้นหาและตัวกรองยังใช้งานได้ระหว่างรอข้อมูลอุปกรณ์ครั้งแรก
      emit(MyItemsLoading(query: _query, statusFilter: _statusFilter));
    }
  }

  void _emitLoaded(
    List<UserItem> items, {
    bool isRefreshing = false,
    String? refreshError,
  }) {
    emit(
      MyItemsLoaded(
        items,
        query: _query,
        statusFilter: _statusFilter,
        isRefreshing: isRefreshing,
        refreshError: refreshError,
      ),
    );
  }
}
