import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/home_repository.dart';
import '../../domain/usecases/get_home_feed_usecase.dart';
import 'home_event.dart';
import 'home_state.dart';

/// BLoC ควบคุมการทำงานของหน้า Home Feed
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required this.getHomeFeed,
    required this.homeRepository,
  }) : super(const HomeInitial()) {
    on<LoadHomeFeedStarted>(_onLoadHomeFeedStarted);
    on<CategoryFilterChanged>(_onCategoryFilterChanged);
    on<ApplyFilterRequested>(_onApplyFilterRequested);
    on<ClearFilterRequested>(_onClearFilterRequested);
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<ToggleFavoriteRequested>(_onToggleFavoriteRequested);
    on<RefreshHomeFeedRequested>(_onRefreshHomeFeedRequested);
  }

  final GetHomeFeedUseCase getHomeFeed;
  final HomeRepository homeRepository;

  Future<void> _onLoadHomeFeedStarted(
    LoadHomeFeedStarted event,
    Emitter<HomeState> emit,
  ) async {
    emit(const HomeLoading());
    try {
      final data = await getHomeFeed(
        categoryId: 'all',
        searchQuery: '',
      );

      emit(
        HomeLoaded(
          categories: data.categories,
          selectedCategoryId: 'all',
          searchQuery: '',
          curatedItems: data.curatedItems,
          nearbyItems: data.nearbyItems,
        ),
      );
    } catch (e) {
      emit(HomeError('ไม่สามารถโหลดข้อมูลหน้าหลักได้: ${e.toString()}'));
    }
  }

  Future<void> _onCategoryFilterChanged(
    CategoryFilterChanged event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    if (currentState.selectedCategoryId == event.categoryId) return;

    try {
      final nearby = await homeRepository.getNearbyItems(
        categoryId: event.categoryId,
        searchQuery: currentState.searchQuery,
        minPrice: currentState.minPrice,
        maxPrice: currentState.maxPrice,
        minRating: currentState.minRating,
      );

      emit(
        currentState.copyWith(
          selectedCategoryId: event.categoryId,
          nearbyItems: nearby,
        ),
      );
    } catch (_) {
      // จัดการกรณีผิดพลาดโดยคงสถานะเดิม
    }
  }

  Future<void> _onApplyFilterRequested(
    ApplyFilterRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    try {
      final nearby = await homeRepository.getNearbyItems(
        categoryId: event.categoryId,
        searchQuery: currentState.searchQuery,
        minPrice: event.minPrice,
        maxPrice: event.maxPrice,
        minRating: event.minRating,
      );

      emit(
        currentState.copyWith(
          selectedCategoryId: event.categoryId,
          nearbyItems: nearby,
          minPrice: () => event.minPrice,
          maxPrice: () => event.maxPrice,
          minRating: () => event.minRating,
        ),
      );
    } catch (_) {
      // จัดการกรณีผิดพลาด
    }
  }

  Future<void> _onClearFilterRequested(
    ClearFilterRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    try {
      final nearby = await homeRepository.getNearbyItems(
        categoryId: 'all',
        searchQuery: currentState.searchQuery,
      );

      emit(
        currentState.copyWith(
          selectedCategoryId: 'all',
          nearbyItems: nearby,
          minPrice: () => null,
          maxPrice: () => null,
          minRating: () => null,
        ),
      );
    } catch (_) {
      // จัดการกรณีผิดพลาด
    }
  }

  Future<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    try {
      final nearby = await homeRepository.getNearbyItems(
        categoryId: currentState.selectedCategoryId,
        searchQuery: event.query,
        minPrice: currentState.minPrice,
        maxPrice: currentState.maxPrice,
        minRating: currentState.minRating,
      );

      emit(
        currentState.copyWith(
          searchQuery: event.query,
          nearbyItems: nearby,
        ),
      );
    } catch (_) {
      // จัดการกรณีผิดพลาด
    }
  }

  Future<void> _onToggleFavoriteRequested(
    ToggleFavoriteRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    final isFav = await homeRepository.toggleFavorite(event.itemId);

    final updatedCurated = currentState.curatedItems.map((item) {
      if (item.id == event.itemId) {
        return item.copyWith(isFavorite: isFav);
      }
      return item;
    }).toList();

    final updatedNearby = currentState.nearbyItems.map((item) {
      if (item.id == event.itemId) {
        return item.copyWith(isFavorite: isFav);
      }
      return item;
    }).toList();

    emit(
      currentState.copyWith(
        curatedItems: updatedCurated,
        nearbyItems: updatedNearby,
      ),
    );
  }

  Future<void> _onRefreshHomeFeedRequested(
    RefreshHomeFeedRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    final categoryId = currentState is HomeLoaded ? currentState.selectedCategoryId : 'all';
    final query = currentState is HomeLoaded ? currentState.searchQuery : '';

    if (currentState is HomeLoaded) {
      emit(currentState.copyWith(isRefreshing: true));
    }

    try {
      final data = await getHomeFeed(
        categoryId: categoryId,
        searchQuery: query,
      );

      emit(
        HomeLoaded(
          categories: data.categories,
          selectedCategoryId: categoryId,
          searchQuery: query,
          curatedItems: data.curatedItems,
          nearbyItems: data.nearbyItems,
          minPrice: currentState is HomeLoaded ? currentState.minPrice : null,
          maxPrice: currentState is HomeLoaded ? currentState.maxPrice : null,
          minRating: currentState is HomeLoaded ? currentState.minRating : null,
          isRefreshing: false,
        ),
      );
    } catch (e) {
      if (currentState is HomeLoaded) {
        emit(currentState.copyWith(isRefreshing: false));
      } else {
        emit(HomeError('เกิดข้อผิดพลาดในการรีเฟรชข้อมูล: ${e.toString()}'));
      }
    }
  }
}

