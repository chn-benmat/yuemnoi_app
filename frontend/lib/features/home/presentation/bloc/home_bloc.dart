import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/favorite_service.dart';
import '../../../../core/services/item_catalog_service.dart';
import '../../domain/entities/feed_item.dart';
import '../../domain/repositories/home_repository.dart';
import '../../domain/usecases/get_home_feed_usecase.dart';
import 'home_event.dart';
import 'home_state.dart';

/// BLoC ควบคุมการทำงานของหน้า Home Feed
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({required this.getHomeFeed, required this.homeRepository})
    : super(const HomeInitial()) {
    on<LoadHomeFeedStarted>(_onLoadHomeFeedStarted);
    on<CategoryFilterChanged>(_onCategoryFilterChanged);
    on<ApplyFilterRequested>(_onApplyFilterRequested);
    on<ClearFilterRequested>(_onClearFilterRequested);
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<ToggleFavoriteRequested>(_onToggleFavoriteRequested);
    on<FavoriteSetChanged>(_onFavoriteSetChanged);
    on<RefreshHomeFeedRequested>(_onRefreshHomeFeedRequested);
    _favoriteListener = () => add(const FavoriteSetChanged());
    FavoriteService.instance.favoritesNotifier.addListener(_favoriteListener);
    _catalogSubscription = ItemCatalogService.instance.changes.listen((_) {
      add(const RefreshHomeFeedRequested());
    });
  }

  final GetHomeFeedUseCase getHomeFeed;
  final HomeRepository homeRepository;
  late final void Function() _favoriteListener;
  late final StreamSubscription<void> _catalogSubscription;

  @override
  Future<void> close() async {
    await _catalogSubscription.cancel();
    FavoriteService.instance.favoritesNotifier.removeListener(
      _favoriteListener,
    );
    return super.close();
  }

  Future<void> _onLoadHomeFeedStarted(
    LoadHomeFeedStarted event,
    Emitter<HomeState> emit,
  ) async {
    emit(const HomeLoading());
    try {
      final data = await getHomeFeed(categoryId: 'all', searchQuery: '');

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
      emit(const HomeError('ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาลองใหม่'));
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
          searchQuery: currentState.searchQuery,
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
          searchQuery: currentState.searchQuery,
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
          searchQuery: currentState.searchQuery,
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
          searchErrorMessage: null,
        ),
      );
    } catch (_) {
      if (event.query.trim().isNotEmpty) {
        emit(
          currentState.copyWith(
            searchQuery: event.query,
            nearbyItems: const [],
            searchErrorMessage: 'ไม่มีการเชื่อมต่ออินเตอร์เน็ตกรุณาลองใหม่',
          ),
        );
      }
    }
  }

  Future<void> _onToggleFavoriteRequested(
    ToggleFavoriteRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    late final bool isFav;
    try {
      isFav = await homeRepository.toggleFavorite(event.itemId);
    } catch (error) {
      emit(currentState.copyWith(favoriteErrorMessage: error.toString()));
      return;
    }

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

  void _onFavoriteSetChanged(
    FavoriteSetChanged event,
    Emitter<HomeState> emit,
  ) {
    final currentState = state;
    if (currentState is! HomeLoaded) return;
    final favorites = FavoriteService.instance.favoritesNotifier.value;

    List<FeedItem> update(List<FeedItem> items) => items
        .map(
          (item) => item.copyWith(
            isFavorite: favorites.contains(int.tryParse(item.id)),
          ),
        )
        .toList();

    emit(
      currentState.copyWith(
        curatedItems: update(currentState.curatedItems),
        nearbyItems: update(currentState.nearbyItems),
      ),
    );
  }

  Future<void> _onRefreshHomeFeedRequested(
    RefreshHomeFeedRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    final categoryId = currentState is HomeLoaded
        ? currentState.selectedCategoryId
        : 'all';
    final query = currentState is HomeLoaded ? currentState.searchQuery : '';

    if (currentState is HomeLoaded) {
      emit(const HomeLoading());
    }

    homeRepository.clearCache();

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
      const message = 'ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาลองใหม่';
      emit(const HomeError(message));
    }
  }
}
