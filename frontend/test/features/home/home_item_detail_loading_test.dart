import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/item_detail_route_args.dart';
import 'package:frontend/features/home/data/models/feed_item_model.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/domain/entities/feed_item.dart';
import 'package:frontend/features/home/domain/repositories/home_repository.dart';
import 'package:frontend/features/home/domain/usecases/get_home_feed_usecase.dart';
import 'package:frontend/features/home/presentation/bloc/home_bloc.dart';
import 'package:frontend/features/home/presentation/bloc/home_event.dart';
import 'package:frontend/features/home/presentation/pages/home_feed_view.dart';
import 'package:frontend/features/home/presentation/pages/equipment_search_screen.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/item_detail/domain/repositories/item_detail_repository.dart';
import 'package:frontend/features/item_detail/domain/usecases/get_item_detail_usecase.dart';
import 'package:frontend/features/item_detail/domain/usecases/update_item_usecase.dart';
import 'package:frontend/features/item_detail/presentation/bloc/item_detail_bloc.dart';
import 'package:frontend/features/item_detail/presentation/pages/item_detail.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HomeRepository implements HomeRepository {
  _HomeRepository(this.item);
  final FeedItem item;
  @override
  void clearCache({bool rotateRecommendations = true}) {}
  @override
  Future<List<FeedCategory>> getCategories() async => const [];
  @override
  Future<List<FeedItem>> getCuratedItems() async => [item];
  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async => [item];
  @override
  Future<bool> toggleFavorite(String itemId) async => false;
}

class _PendingDetailRepository implements ItemDetailRepository {
  @override
  Future<ItemDetail> fetchById(int itemId) => Completer<ItemDetail>().future;
  @override
  Future<ItemDetail> update(ItemEditDraft draft) =>
      Completer<ItemDetail>().future;
  @override
  Future<ItemDetail> setVisibility(int itemId, {required bool hidden}) =>
      Completer<ItemDetail>().future;
  @override
  Future<void> delete(int itemId) => Completer<void>().future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final fromSearch in [false, true]) {
    for (final isOwner in [true, false]) {
      testWidgets(
        '${fromSearch ? 'search' : 'home'} selects ${isOwner ? 'owner' : 'renter'} detail skeleton before fetching',
        (tester) async {
          final item = FeedItemModel.fromJson({
            'id': 7,
            'item_name': 'Camera',
            'is_owner': isOwner,
          }).copyWith(isFavorite: true).toEntity();
          final repository = _HomeRepository(item);
          final homeBloc = HomeBloc(
            getHomeFeed: GetHomeFeedUseCase(repository),
            homeRepository: repository,
          )..add(const LoadHomeFeedStarted());
          final detailRepository = _PendingDetailRepository();
          final detailBloc = ItemDetailBloc(
            getItem: GetItemDetailUseCase(detailRepository),
            updateItem: UpdateItemUseCase(detailRepository),
          );
          final router = GoRouter(
            initialLocation: '/home',
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => BlocProvider.value(
                  value: homeBloc,
                  child: fromSearch
                      ? EquipmentSearchScreen(
                          initialQuery: 'Camera',
                          initialCuratedItems: [item],
                          homeRepository: repository,
                        )
                      : const HomeFeedView(),
                ),
              ),
              GoRoute(
                path: '/items/:id',
                builder: (_, state) => BlocProvider.value(
                  value: detailBloc,
                  child: ItemDetailScreen(
                    itemId: int.parse(state.pathParameters['id']!),
                    ownerLoadingLayout:
                        (state.extra as ItemDetailRouteArgs).ownerLoadingLayout,
                  ),
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          addTearDown(homeBloc.close);
          addTearDown(detailBloc.close);
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('shopee-card-7')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.byKey(
              ValueKey(
                isOwner ? 'owner-item-detail-skeleton' : 'item-detail-skeleton',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.byIcon(Icons.share_outlined),
            isOwner ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
