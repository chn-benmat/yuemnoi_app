import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/domain/entities/feed_item.dart';
import 'package:frontend/features/home/domain/repositories/home_repository.dart';
import 'package:frontend/features/home/domain/usecases/get_home_feed_usecase.dart';
import 'package:frontend/features/home/presentation/bloc/home_bloc.dart';
import 'package:frontend/features/home/presentation/bloc/home_event.dart';
import 'package:frontend/features/home/presentation/bloc/home_state.dart';
import 'package:frontend/features/home/presentation/pages/home_feed_view.dart';
import 'package:frontend/features/home/presentation/widgets/category_filter_chips.dart';
import 'package:frontend/features/home/presentation/widgets/home_search_bar.dart';
import 'package:frontend/features/home/presentation/widgets/shopee_product_card.dart';

class _DelayedHomeRepository implements HomeRepository {
  _DelayedHomeRepository({this.items = const []});

  final List<FeedItem> items;
  final categories = Completer<List<FeedCategory>>();

  @override
  void clearCache({bool rotateRecommendations = true}) {}

  @override
  Future<List<FeedCategory>> getCategories() => categories.future;

  @override
  Future<List<FeedItem>> getCuratedItems() async => items;

  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async => const [];

  @override
  Future<bool> toggleFavorite(String itemId) async => false;
}

void main() {
  testWidgets('home skeleton photo matches the loaded product photo bounds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _DelayedHomeRepository(
      items: const [
        FeedItem(
          id: '7',
          title: 'Camera',
          categoryId: 'camera',
          price: 500,
          priceUnit: '/ วัน',
          rating: 0,
          reviewCount: 0,
          distanceKm: 0,
          isVerified: false,
          ownerName: 'Owner',
          imageUrl: '',
        ),
      ],
    );
    final bloc = HomeBloc(
      getHomeFeed: GetHomeFeedUseCase(repository),
      homeRepository: repository,
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const HomeFeedView()),
      ),
    );
    final loadingPhoto = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('home-feed-skeleton')),
            matching: find.byType(SkeletonBox),
          )
          .first,
    );
    bloc.add(const LoadHomeFeedStarted());
    repository.categories.complete(const []);
    await tester.pumpAndSettle();
    final loadedPhoto = tester.getRect(
      find
          .descendant(
            of: find.byType(ShopeeProductCard),
            matching: find.byType(AspectRatio),
          )
          .first,
    );
    expect(loadingPhoto, loadedPhoto);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps home controls visible while only products show skeletons',
    (tester) async {
      final repository = _DelayedHomeRepository();
      final bloc = HomeBloc(
        getHomeFeed: GetHomeFeedUseCase(repository),
        homeRepository: repository,
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(value: bloc, child: const HomeFeedView()),
        ),
      );

      expect(find.byKey(const ValueKey('home-feed-skeleton')), findsOneWidget);
      expect(find.byType(SkeletonShimmer), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(HomeSearchBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-favorites-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('category-chip-camera')),
        findsOneWidget,
      );
      expect(find.byType(CategoryFilterChips), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SkeletonShimmer),
          matching: find.byType(HomeSearchBar),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(SkeletonShimmer),
          matching: find.byType(CategoryFilterChips),
        ),
        findsNothing,
      );
      final searchPosition = tester.getTopLeft(find.byType(HomeSearchBar));
      final categoriesPosition = tester.getTopLeft(
        find.byType(CategoryFilterChips),
      );

      bloc.add(const LoadHomeFeedStarted());
      await tester.pump();

      expect(bloc.state, isA<HomeLoading>());
      expect(find.byType(HomeSearchBar), findsOneWidget);
      expect(find.byType(CategoryFilterChips), findsOneWidget);
      expect(find.byKey(const ValueKey('home-feed-skeleton')), findsOneWidget);

      repository.categories.complete(const []);
      await tester.pumpAndSettle();

      expect(bloc.state, isA<HomeLoaded>());
      expect(find.byType(SkeletonShimmer), findsNothing);
      expect(tester.getTopLeft(find.byType(HomeSearchBar)), searchPosition);
      expect(
        tester.getTopLeft(find.byType(CategoryFilterChips)),
        categoriesPosition,
      );
    },
  );
}
