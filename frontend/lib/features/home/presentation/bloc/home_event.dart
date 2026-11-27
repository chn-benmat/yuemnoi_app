import 'package:equatable/equatable.dart';

/// อีเวนต์ทั้งหมดของ HomeBloc
abstract class HomeEvent extends Equatable {
  const HomeEvent();

  @override
  List<Object?> get props => [];
}

sealed class HomeFeedQueryEvent extends HomeEvent {
  const HomeFeedQueryEvent();
}

/// อีเวนต์เริ่มโหลดข้อมูลหน้า Home Feed
class LoadHomeFeedStarted extends HomeFeedQueryEvent {
  const LoadHomeFeedStarted();
}

/// อีเวนต์เปลี่ยนหมวดหมู่ตัวกรอง
class CategoryFilterChanged extends HomeFeedQueryEvent {
  const CategoryFilterChanged(this.categoryId);

  final String categoryId;

  @override
  List<Object?> get props => [categoryId];
}

/// อีเวนต์ปรับเปลี่ยนเงื่อนไขตัวกรอง (หมวดหมู่, ราคา, คะแนนรีวิว)
class ApplyFilterRequested extends HomeFeedQueryEvent {
  const ApplyFilterRequested({
    this.categoryId = 'all',
    this.minPrice,
    this.maxPrice,
    this.minRating,
  });

  final String categoryId;
  final int? minPrice;
  final int? maxPrice;
  final double? minRating;

  @override
  List<Object?> get props => [categoryId, minPrice, maxPrice, minRating];
}

/// อีเวนต์ล้างตัวกรองทั้งหมดกลับสู่ค่าเริ่มต้น
class ClearFilterRequested extends HomeFeedQueryEvent {
  const ClearFilterRequested();
}

/// อีเวนต์เปลี่ยนคำค้นหา
class SearchQueryChanged extends HomeFeedQueryEvent {
  const SearchQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// อีเวนต์สลับสถานะรายการโปรด
class ToggleFavoriteRequested extends HomeEvent {
  const ToggleFavoriteRequested(this.itemId);

  final String itemId;

  @override
  List<Object?> get props => [itemId];
}

/// อัปเดตสถานะหัวใจเมื่อ favorite เปลี่ยนจากหน้าหรือบัญชีอื่นในแอป
class FavoriteSetChanged extends HomeEvent {
  const FavoriteSetChanged();
}

/// อีเวนต์ดึงข้อมูลใหม่เมื่อผู้ใช้รีเฟรชหรือรายการเปลี่ยน
class RefreshHomeFeedRequested extends HomeFeedQueryEvent {
  const RefreshHomeFeedRequested({this.inBackground = false});

  final bool inBackground;

  @override
  List<Object?> get props => [inBackground];
}
