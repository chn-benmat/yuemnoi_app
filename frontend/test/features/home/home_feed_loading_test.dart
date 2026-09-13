import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/domain/entities/feed_item.dart';
import 'package:frontend/features/home/domain/repositories/home_repository.dart';
import 'package:frontend/features/home/domain/usecases/get_home_feed_usecase.dart';
import 'package:frontend/features/home/presentation/bloc/home_bloc.dart';
import 'package:frontend/features/home/presentation/pages/home_feed_view.dart';

class _EmptyHomeRepository implements HomeRepository {
  @override
  void clearCache() {}

  @override
  Future<List<FeedCategory>> getCategories() async => const [];

  @override
  Future<List<FeedItem>> getCuratedItems() async => const [];

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
  testWidgets('shows product skeletons while the home feed is loading', (
    tester,
  ) async {
    final repository = _EmptyHomeRepository();
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
    expect(find.byType(SkeletonShimmer), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
