import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/network/auth_session.dart';
import '../../../../core/services/favorite_service.dart';
import '../../../../core/services/item_catalog_service.dart';
import '../../../../core/services/recommendation_location_service.dart';
import '../../domain/entities/feed_item.dart';
import '../../domain/repositories/home_repository.dart';
import '../../domain/usecases/get_home_feed_usecase.dart';
import 'home_event.dart';
import 'home_state.dart';

/// BLoC ควบคุมการทำงานของหน้า Home Feed
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required this.getHomeFeed,
    required this.homeRepository,
    Stream<void> feedChanges = const Stream.empty(),
    ValueListenable<LatLng?>? position,
  }) : _position = position ?? RecommendationLocationService.instance.position,
       super(const HomeInitial()) {
    // จัดคิวร่วมกันเพื่อไม่ให้ผลรีเฟรชเขียนทับคำค้นหาหรือตัวกรองใหม่
    on<HomeFeedQueryEvent>(
      (event, emit) => switch (event) {
        LoadHomeFeedStarted() => _onLoadHomeFeedStarted(event, emit),
        CategoryFilterChanged() => _onCategoryFilterChanged(event, emit),
        ApplyFilterRequested() => _onApplyFilterRequested(event, emit),
        ClearFilterRequested() => _onClearFilterRequested(event, emit),
        SearchQueryChanged() => _onSearchQueryChanged(event, emit),
        RefreshHomeFeedRequested() => _onRefreshHomeFeedRequested(event, emit),
        LoadMoreHomeFeedRequested() => _onLoadMore(event, emit),
        HomeRecommendationsChanged() => _onRecommendationsChanged(emit),
      },
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<ToggleFavoriteRequested>(_onToggleFavoriteRequested);
    on<FavoriteSetChanged>(_onFavoriteSetChanged);
    on<_HomeAccountChanged>((_, emit) {
      emit(const HomeLoading());
      add(const LoadHomeFeedStarted());
    });
    AuthSession.accountChanges.addListener(_onAccountChanged);
    _position.addListener(_onPositionChanged);
    _favoriteListener = () => add(const FavoriteSetChanged());
    FavoriteService.instance.favoritesNotifier.addListener(_favoriteListener);
    _catalogSubscription = ItemCatalogService.instance.changes.listen(
      _queueBackgroundRefresh,
    );
    _realtimeSubscription = feedChanges.listen(_queueBackgroundRefresh);
  }

  final GetHomeFeedUseCase getHomeFeed;
  final HomeRepository homeRepository;
  final ValueListenable<LatLng?> _position;
  late final void Function() _favoriteListener;
  late final StreamSubscription<void> _catalogSubscription;
  late final StreamSubscription<void> _realtimeSubscription;
  bool _backgroundRefreshQueued = false;
  String? _accountId = AuthSession.accountChanges.value.userId;
  int _accountRevision = 0;
  int _recommendationRevision = 0;
  int _loadedRecommendationRevision = 0;
  final _recentCategories = <String>[];
  final _consumedCursors = <String>{};

  void _onAccountChanged() {
    if (isClosed) return;
    final userId = AuthSession.accountChanges.value.userId;
    if (_accountId == userId) {
      if (userId != null && getHomeFeed.supportsRankedFeed) {
        _queueBackgroundRefresh(null);
      }
      return;
    }
    _accountId = userId;
    _accountRevision++;
    _recentCategories.clear();
    _consumedCursors.clear();
    add(const _HomeAccountChanged());
  }

  void _onPositionChanged() {
    if (isClosed) return;
    _recommendationRevision++;
    add(const HomeRecommendationsChanged());
  }

  void Function(String) captureCategoryInterest() {
    final revision = _accountRevision;
    return (categoryId) {
      if (isClosed || revision != _accountRevision) return;
      _recordCategoryInterest(categoryId);
    };
  }

  void _recordCategoryInterest(String categoryId) {
    if (categoryId == 'all' || categoryId.isEmpty) return;
    if (_recentCategories.isNotEmpty && _recentCategories.first == categoryId) {
      return;
    }
    _recentCategories.remove(categoryId);
    _recentCategories.insert(0, categoryId);
    if (_recentCategories.length > 10) _recentCategories.removeLast();
    _recommendationRevision++;
  }

  void _queueBackgroundRefresh(void _) {
    if (isClosed || _backgroundRefreshQueued) return;
    _backgroundRefreshQueued = true;
    add(const RefreshHomeFeedRequested(inBackground: true));
  }

  @override
  Future<void> close() async {
    AuthSession.accountChanges.removeListener(_onAccountChanged);
    _position.removeListener(_onPositionChanged);
    FavoriteService.instance.favoritesNotifier.removeListener(
      _favoriteListener,
    );
    await Future.wait([
      _catalogSubscription.cancel(),
      _realtimeSubscription.cancel(),
    ]);
    return super.close();
  }

  Future<void> _onLoadHomeFeedStarted(
    LoadHomeFeedStarted event,
    Emitter<HomeState> emit,
  ) async {
    emit(const HomeLoading());
    final accountRevision = _accountRevision;
    try {
      final loaded = await _loadFeed();
      if (accountRevision == _accountRevision) emit(loaded);
    } catch (_) {
      if (accountRevision == _accountRevision) {
        emit(const HomeError('ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาลองใหม่'));
      }
    }
  }

  Future<void> _onCategoryFilterChanged(
    CategoryFilterChanged event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    if (currentState.selectedCategoryId == event.categoryId) return;

    _recordCategoryInterest(event.categoryId);
    await _changeQuery(
      currentState.copyWith(selectedCategoryId: event.categoryId),
      emit,
    );
  }

  Future<void> _onApplyFilterRequested(
    ApplyFilterRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    _recordCategoryInterest(event.categoryId);
    await _changeQuery(
      currentState.copyWith(
        selectedCategoryId: event.categoryId,
        minPrice: () => event.minPrice,
        maxPrice: () => event.maxPrice,
        minRating: () => event.minRating,
      ),
      emit,
    );
  }

  Future<void> _onClearFilterRequested(
    ClearFilterRequested event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    await _changeQuery(
      currentState.copyWith(
        selectedCategoryId: 'all',
        minPrice: () => null,
        maxPrice: () => null,
        minRating: () => null,
      ),
      emit,
    );
  }

  Future<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<HomeState> emit,
  ) async {
    final currentState = state;
    if (currentState is! HomeLoaded) return;

    await _changeQuery(
      currentState.copyWith(searchQuery: event.query),
      emit,
      showSearchError: event.query.trim().isNotEmpty,
    );
  }

  Future<void> _changeQuery(
    HomeLoaded query,
    Emitter<HomeState> emit, {
    bool showSearchError = false,
  }) async {
    final accountRevision = _accountRevision;
    try {
      if (_isDefault(query)) {
        final loaded = await _loadFeed(previous: query);
        if (accountRevision == _accountRevision) emit(loaded);
        return;
      }

      final nearby = await homeRepository.getNearbyItems(
        categoryId: query.selectedCategoryId,
        searchQuery: query.searchQuery,
        minPrice: query.minPrice,
        maxPrice: query.maxPrice,
        minRating: query.minRating,
      );
      if (accountRevision == _accountRevision) {
        emit(
          query.copyWith(
            nearbyItems: nearby,
            hasRankedOrder: false,
            nextCursor: () => null,
          ),
        );
      }
    } catch (_) {
      if (showSearchError && accountRevision == _accountRevision) {
        emit(
          query.copyWith(
            nearbyItems: const [],
            hasRankedOrder: false,
            nextCursor: () => null,
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
    if (state is! HomeLoaded) return;
    final accountRevision = _accountRevision;

    late final bool isFav;
    try {
      isFav = await homeRepository.toggleFavorite(event.itemId);
    } catch (error) {
      if (state case final HomeLoaded currentState
          when accountRevision == _accountRevision) {
        emit(currentState.copyWith(favoriteErrorMessage: error.toString()));
      }
      return;
    }

    final currentState = state;
    if (currentState is! HomeLoaded || accountRevision != _accountRevision) {
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
    if (event.inBackground) _backgroundRefreshQueued = false;
    final currentState = state;
    final previousFeed = currentState is HomeLoaded ? currentState : null;
    if (event.inBackground &&
        previousFeed?.hasRankedOrder == true &&
        _consumedCursors.isNotEmpty &&
        _loadedRecommendationRevision == _recommendationRevision) {
      return;
    }
    final accountRevision = _accountRevision;

    if (previousFeed == null) {
      emit(const HomeLoading());
    } else if (!event.inBackground) {
      emit(previousFeed.copyWith(isRefreshing: true));
    }

    homeRepository.clearCache(rotateRecommendations: !event.inBackground);

    try {
      final loaded = await _loadFeed(previous: previousFeed);
      if (accountRevision == _accountRevision) emit(loaded);
    } catch (_) {
      if (accountRevision != _accountRevision) return;
      if (event.inBackground && previousFeed != null) return;
      const message = 'ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาลองใหม่';
      emit(const HomeError(message));
    }
  }

  bool _isDefault(HomeLoaded state) =>
      !state.hasActiveFilters && state.searchQuery.trim().isEmpty;

  Future<HomeLoaded> _loadFeed({HomeLoaded? previous}) async {
    final revision = _recommendationRevision;
    final position = _position.value;
    final data = await getHomeFeed(
      categoryId: previous?.selectedCategoryId ?? 'all',
      searchQuery: previous?.searchQuery ?? '',
      minPrice: previous?.minPrice,
      maxPrice: previous?.maxPrice,
      minRating: previous?.minRating,
      latitude: position?.latitude,
      longitude: position?.longitude,
      recentCategories: List.of(_recentCategories),
      previousRankedItems: previous?.hasRankedOrder == true
          ? previous!.nearbyItems
          : null,
    );
    _loadedRecommendationRevision = revision;
    _consumedCursors.clear();
    return HomeLoaded(
      categories: data.categories,
      selectedCategoryId: previous?.selectedCategoryId ?? 'all',
      searchQuery: previous?.searchQuery ?? '',
      curatedItems: data.curatedItems,
      nearbyItems: data.nearbyItems,
      minPrice: previous?.minPrice,
      maxPrice: previous?.maxPrice,
      minRating: previous?.minRating,
      hasRankedOrder: data.hasRankedOrder,
      nextCursor: data.nextCursor,
    );
  }

  Future<void> _onRecommendationsChanged(Emitter<HomeState> emit) async {
    final current = state;
    if (getHomeFeed.supportsRankedFeed &&
        current is HomeLoaded &&
        _isDefault(current) &&
        _recommendationRevision != _loadedRecommendationRevision) {
      await _onRefreshHomeFeedRequested(
        const RefreshHomeFeedRequested(inBackground: true),
        emit,
      );
    }
  }

  Future<void> _onLoadMore(
    LoadMoreHomeFeedRequested event,
    Emitter<HomeState> emit,
  ) async {
    final current = state;
    if (current is! HomeLoaded ||
        !current.hasRankedOrder ||
        event.cursor != current.nextCursor ||
        _loadedRecommendationRevision != _recommendationRevision) {
      return;
    }
    final accountRevision = _accountRevision;
    final recommendationRevision = _recommendationRevision;
    emit(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    final position = _position.value;
    final RankedHomePage? page;
    try {
      page = await getHomeFeed.getRankedPage(
        latitude: position?.latitude,
        longitude: position?.longitude,
        recentCategories: List.of(_recentCategories),
        cursor: event.cursor,
      );
    } on RankedHomeCursorInvalid {
      if (accountRevision != _accountRevision) return;
      await _restartRankedFeed(emit, accountRevision);
      return;
    }
    if (accountRevision != _accountRevision) return;
    final latest = state as HomeLoaded;
    if (recommendationRevision != _recommendationRevision) {
      emit(latest.copyWith(isLoadingMore: false, nextCursor: () => null));
      return;
    }
    if (page == null) {
      emit(latest.copyWith(isLoadingMore: false, loadMoreFailed: true));
      return;
    }
    final seen = latest.nearbyItems.map((item) => item.id).toSet();
    _consumedCursors.add(event.cursor);
    final nextCursor = page.nextCursor;
    emit(
      latest.copyWith(
        nearbyItems: [
          ...latest.nearbyItems,
          ...page.items.where((item) => seen.add(item.id)),
        ],
        nextCursor: () =>
            _consumedCursors.contains(nextCursor) ? null : nextCursor,
        isLoadingMore: false,
      ),
    );
  }

  Future<void> _restartRankedFeed(
    Emitter<HomeState> emit,
    int accountRevision,
  ) async {
    final current = state as HomeLoaded;
    try {
      final refreshed = await _loadFeed(previous: current);
      if (accountRevision != _accountRevision) return;
      // ให้ผู้ใช้เลือกโหลดต่อเพื่อเลี่ยงการลองซ้ำทันทีเมื่อเคอร์เซอร์หมดอายุ
      emit(refreshed.copyWith(loadMoreFailed: refreshed.nextCursor != null));
    } catch (_) {
      if (accountRevision != _accountRevision) return;
      emit(current.copyWith(isLoadingMore: false, nextCursor: () => null));
    }
  }
}

class _HomeAccountChanged extends HomeEvent {
  const _HomeAccountChanged();
}
