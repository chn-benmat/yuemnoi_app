import '../../domain/entities/user_item.dart';

enum MyItemsFilter {
  available,
  rented,
  hidden;

  // ใช้เงื่อนไขเดียวกันสำหรับยอดนับและรายการที่แสดง โดยไม่เปลี่ยนสถานะการเช่าจริง
  bool matches(UserItem item) => switch (this) {
    hidden => item.ownerHidden,
    available =>
      !item.ownerHidden && item.listingStatus == UserItemStatus.available,
    rented => !item.ownerHidden && item.listingStatus == UserItemStatus.rented,
  };
}

// คำอธิบาย: State สำหรับหน้าจัดการอุปกรณ์ของฉัน (My Items)
abstract class MyItemsState {
  const MyItemsState({this.query = '', this.statusFilter});

  final String query;
  final MyItemsFilter? statusFilter;
}

class MyItemsInitial extends MyItemsState {
  const MyItemsInitial();
}

class MyItemsLoading extends MyItemsState {
  const MyItemsLoading({super.query, super.statusFilter});
}

class MyItemsLoaded extends MyItemsState {
  final List<UserItem> items;
  final bool isRefreshing;
  final String? refreshError;

  const MyItemsLoaded(
    this.items, {
    super.query,
    super.statusFilter,
    this.isRefreshing = false,
    this.refreshError,
  });

  bool get hasActiveFilters => query.trim().isNotEmpty || statusFilter != null;

  int countFor(MyItemsFilter? status) =>
      status == null ? items.length : items.where(status.matches).length;

  List<UserItem> get visibleItems {
    final search = query.trim().toLowerCase();
    return items
        .where((item) {
          final matchesStatus = statusFilter?.matches(item) ?? true;
          return matchesStatus &&
              (search.isEmpty ||
                  item.title.toLowerCase().contains(search) ||
                  item.category.toLowerCase().contains(search));
        })
        .toList(growable: false);
  }
}

class MyItemsError extends MyItemsState {
  final String message;
  const MyItemsError(this.message, {super.query, super.statusFilter});
}
