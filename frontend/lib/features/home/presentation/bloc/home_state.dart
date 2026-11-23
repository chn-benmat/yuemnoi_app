import 'package:equatable/equatable.dart';

import '../../domain/entities/feed_category.dart';
import '../../domain/entities/feed_item.dart';

/// สถานะทั้งหมดของ HomeBloc
abstract class HomeState extends Equatable {
  const HomeState();

  @override
  List<Object?> get props => [];
}

/// สถานะเริ่มต้น
class HomeInitial extends HomeState {
  const HomeInitial();
}

/// สถานะกำลังโหลดข้อมูล
class HomeLoading extends HomeState {
  const HomeLoading();
}

/// สถานะโหลดข้อมูลสำเร็จและพร้อมแสดงผล
class HomeLoaded extends HomeState {
  const HomeLoaded({
    required this.categories,
    required this.selectedCategoryId,
    required this.searchQuery,
    required this.curatedItems,
    required this.nearbyItems,
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.isRefreshing = false,
    this.favoriteErrorMessage,
    this.searchErrorMessage,
  });

  /// รายการหมวดหมู่ทั้งหมด
  final List<FeedCategory> categories;

  /// หมวดหมู่ที่เลือกอยู่ปัจจุบัน
  final String selectedCategoryId;

  /// คำค้นหาปัจจุบัน
  final String searchQuery;

  /// รายการอุปกรณ์แนะนำประจำวัน (Curated)
  final List<FeedItem> curatedItems;

  /// รายการอุปกรณ์ใกล้เคียง (Nearby)
  final List<FeedItem> nearbyItems;

  /// ราคาต่ำสุดที่กรอง
  final int? minPrice;

  /// ราคาสูงสุดที่กรอง
  final int? maxPrice;

  /// คะแนนรีวิวขั้นต่ำที่กรอง (เช่น 4.0, 4.5)
  final double? minRating;

  /// กำลังรีเฟรชข้อมูลในเบื้องหลังหรือไม่
  final bool isRefreshing;

  /// Error จากการบันทึก favorite ให้หน้า Home แสดงแก่ผู้ใช้
  final String? favoriteErrorMessage;

  /// ข้อความเมื่อค้นหาไม่ได้เพราะเครือข่ายไม่พร้อม
  final String? searchErrorMessage;

  /// มีการใช้ตัวกรองอยู่หรือไม่
  bool get hasActiveFilters =>
      selectedCategoryId != 'all' ||
      minPrice != null ||
      maxPrice != null ||
      minRating != null;

  HomeLoaded copyWith({
    List<FeedCategory>? categories,
    String? selectedCategoryId,
    String? searchQuery,
    List<FeedItem>? curatedItems,
    List<FeedItem>? nearbyItems,
    int? Function()? minPrice,
    int? Function()? maxPrice,
    double? Function()? minRating,
    bool? isRefreshing,
    String? favoriteErrorMessage,
    String? searchErrorMessage,
  }) {
    return HomeLoaded(
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      searchQuery: searchQuery ?? this.searchQuery,
      curatedItems: curatedItems ?? this.curatedItems,
      nearbyItems: nearbyItems ?? this.nearbyItems,
      minPrice: minPrice != null ? minPrice() : this.minPrice,
      maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
      minRating: minRating != null ? minRating() : this.minRating,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      favoriteErrorMessage: favoriteErrorMessage,
      searchErrorMessage: searchErrorMessage,
    );
  }

  @override
  List<Object?> get props => [
    categories,
    selectedCategoryId,
    searchQuery,
    curatedItems,
    nearbyItems,
    minPrice,
    maxPrice,
    minRating,
    isRefreshing,
    favoriteErrorMessage,
    searchErrorMessage,
  ];
}

/// สถานะเกิดข้อผิดพลาดในการโหลดข้อมูล
class HomeError extends HomeState {
  const HomeError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
