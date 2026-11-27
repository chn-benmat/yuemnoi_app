import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/domain/entities/feed_item.dart';
import 'package:frontend/features/home/domain/repositories/home_repository.dart';
import 'package:frontend/features/home/domain/usecases/get_home_feed_usecase.dart';
import 'package:frontend/features/home/presentation/bloc/home_bloc.dart';
import 'package:frontend/features/home/presentation/bloc/home_event.dart';
import 'package:frontend/features/home/presentation/bloc/home_state.dart';

class _MockFailingHomeRepository implements HomeRepository {
  @override
  Future<List<FeedCategory>> getCategories() async {
    throw Exception('Connection failed');
  }

  @override
  Future<List<FeedItem>> getCuratedItems() async {
    throw Exception('Connection failed');
  }

  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async {
    throw Exception('Connection failed');
  }

  @override
  Future<bool> toggleFavorite(String itemId) async => false;

  @override
  void clearCache({bool rotateRecommendations = true}) {}
}

class _CatalogHomeRepository implements HomeRepository {
  static const camera = FeedItem(
    id: '1',
    title: 'Camera',
    categoryId: 'camera',
    price: 500,
    priceUnit: '/วัน',
    rating: 4.5,
    reviewCount: 2,
    isVerified: false,
    ownerName: 'Owner',
    imageUrl: '',
  );

  List<FeedItem> items = [camera, camera.copyWith(id: '2', price: 1000)];
  Future<void>? refreshGate;

  @override
  Future<List<FeedCategory>> getCategories() async => [];

  @override
  Future<List<FeedItem>> getCuratedItems() async {
    await refreshGate;
    return items;
  }

  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async => [
    for (final item in items)
      if ((categoryId == 'all' || item.categoryId == categoryId) &&
          item.title.contains(searchQuery ?? '') &&
          item.price >= (minPrice ?? 0) &&
          item.price <= (maxPrice ?? double.infinity) &&
          item.rating >= (minRating ?? 0))
        item,
  ];

  @override
  Future<bool> toggleFavorite(String itemId) async => false;

  @override
  void clearCache({bool rotateRecommendations = true}) {}
}

void main() {
  test(
    'refreshes availability in place with the active search and filters',
    () async {
      final repo = _CatalogHomeRepository();
      final feedChanges = StreamController<void>();
      final bloc = HomeBloc(
        homeRepository: repo,
        getHomeFeed: GetHomeFeedUseCase(repo),
        feedChanges: feedChanges.stream,
      );
      addTearDown(feedChanges.close);
      addTearDown(bloc.close);
      bloc.add(const LoadHomeFeedStarted());
      await bloc.stream.firstWhere((s) => s is HomeLoaded);
      bloc.add(
        const ApplyFilterRequested(
          categoryId: 'camera',
          minPrice: 200,
          maxPrice: 700,
          minRating: 4,
        ),
      );
      await bloc.stream.firstWhere(
        (s) => s is HomeLoaded && s.hasActiveFilters,
      );
      bloc.add(const SearchQueryChanged('Camera'));
      await bloc.stream.firstWhere(
        (s) => s is HomeLoaded && s.searchQuery == 'Camera',
      );

      final gate = Completer<void>();
      repo.refreshGate = gate.future;
      repo.items = [
        repo.items.first.copyWith(isRentalOccupied: true),
        repo.items.last,
      ];
      final updated = bloc.stream.first;
      feedChanges.add(null);
      await Future<void>.delayed(Duration.zero);
      final stateWhileRefreshing = bloc.state;
      gate.complete();

      expect(stateWhileRefreshing, isA<HomeLoaded>());
      final state = await updated as HomeLoaded;
      expect(state.searchQuery, 'Camera');
      expect(state.selectedCategoryId, 'camera');
      expect(state.nearbyItems.map((item) => item.id), ['1']);
      expect(state.nearbyItems.single.isRentalOccupied, isTrue);
    },
  );

  group('HomeBloc Fallback Error handling', () {
    test(
      'emits HomeError with connection error message when server is down',
      () async {
        final repo = _MockFailingHomeRepository();
        final bloc = HomeBloc(
          homeRepository: repo,
          getHomeFeed: GetHomeFeedUseCase(repo),
        );

        bloc.add(const LoadHomeFeedStarted());

        await expectLater(
          bloc.stream,
          emitsInOrder([
            const HomeLoading(),
            const HomeError('ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาลองใหม่'),
          ]),
        );

        bloc.close();
      },
    );
  });
}
