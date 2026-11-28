import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/auth_session.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/domain/entities/feed_item.dart';
import 'package:frontend/features/home/domain/repositories/home_repository.dart';
import 'package:frontend/features/home/domain/usecases/get_home_feed_usecase.dart';
import 'package:frontend/features/home/presentation/bloc/home_bloc.dart';
import 'package:frontend/features/home/presentation/bloc/home_event.dart';
import 'package:frontend/features/home/presentation/pages/home_feed_view.dart';
import 'package:frontend/features/rental_item/domain/entities/rental_item.dart';
import 'package:frontend/features/rental_item/domain/repositories/rental_item_repository.dart';
import 'package:frontend/features/rental_item/domain/usecases/create_rental_item_usecase.dart';
import 'package:frontend/features/rental_item/presentation/bloc/rental_item_bloc.dart';
import 'package:frontend/features/rental_item/presentation/bloc/rental_item_event.dart';
import 'package:frontend/features/rental_item/presentation/pages/add_rental_item.dart';
import 'package:go_router/go_router.dart';

class _CatalogRepository implements HomeRepository, RentalItemRepository {
  _CatalogRepository({this.failCreation = false});

  final bool failCreation;
  final List<FeedItem> _items = [];
  List<FeedItem>? _cachedItems;
  int cacheClearCount = 0;

  @override
  Future<List<FeedCategory>> getCategories() async => const [];

  @override
  Future<List<FeedItem>> getCuratedItems() async =>
      _cachedItems ??= List.of(_items);

  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async => _cachedItems ??= List.of(_items);

  @override
  Future<bool> toggleFavorite(String itemId) async => false;

  @override
  void clearCache({bool rotateRecommendations = true}) {
    cacheClearCount++;
    _cachedItems = null;
  }

  @override
  Future<RentalItem> create(RentalItemDraft draft) async {
    if (failCreation) {
      throw const RentalItemException('เพิ่มอุปกรณ์ไม่สำเร็จ');
    }
    _items.add(
      FeedItem(
        id: '1',
        title: draft.name,
        categoryId: 'camera',
        price: draft.hourlyRate ?? draft.dailyRate ?? 0,
        priceUnit: '/วัน',
        rating: 0,
        reviewCount: 0,
        distanceKm: 0,
        isVerified: false,
        ownerName: 'เจ้าของอุปกรณ์',
        imageUrl: '',
      ),
    );
    return const RentalItem(id: 1, imageUrls: []);
  }

  @override
  void close() {}
}

void main() {
  setUp(() => AuthSession.saveAccessToken('test-token'));
  tearDown(AuthSession.clear);

  for (final scenario in [
    (
      name: 'shows a newly created item after returning home without refresh',
      throughMyItems: true,
      submit: true,
      failCreation: false,
    ),
    (
      name: 'shows a newly created item when returning directly home',
      throughMyItems: false,
      submit: true,
      failCreation: false,
    ),
    (
      name: 'does not reload home when adding an item is canceled',
      throughMyItems: true,
      submit: false,
      failCreation: false,
    ),
    (
      name: 'keeps the add form open without reloading home when saving fails',
      throughMyItems: true,
      submit: true,
      failCreation: true,
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      final repository = _CatalogRepository(
        failCreation: scenario.failCreation,
      );
      final homeBloc = HomeBloc(
        getHomeFeed: GetHomeFeedUseCase(repository),
        homeRepository: repository,
      )..add(const LoadHomeFeedStarted());
      final rentalBloc = RentalItemBloc(
        createItem: CreateRentalItemUseCase(repository),
      );
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => BlocProvider.value(
              value: homeBloc,
              child: const HomeFeedView(),
            ),
          ),
          GoRoute(
            path: '/my-items',
            builder: (_, _) => const Scaffold(body: Text('อุปกรณ์ของฉัน')),
          ),
          GoRoute(
            path: '/add',
            builder: (_, _) => BlocProvider.value(
              value: rentalBloc,
              child: const AddRentalItemScreen(),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(homeBloc.close);
      addTearDown(rentalBloc.close);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shopee-card-1')), findsNothing);

      if (scenario.throughMyItems) {
        router.push<void>('/my-items');
        await tester.pumpAndSettle();
      }
      router.push<RentalItem>('/add');
      await tester.pumpAndSettle();

      if (scenario.submit) {
        rentalBloc.add(
          RentalItemSubmitted(
            RentalItemDraft(
              name: 'กล้องที่เพิ่งเพิ่ม',
              category: 'กล้องและอุปกรณ์ถ่ายภาพ',
              description: 'อุปกรณ์ทดสอบ',
              dailyRate: 540,
              images: [
                RentalItemImage(bytes: Uint8List(1), fileName: 'camera.png'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      if (scenario.failCreation) {
        expect(find.byType(AddRentalItemScreen), findsOneWidget);
        expect(find.text('เพิ่มอุปกรณ์ไม่สำเร็จ'), findsOneWidget);
      }
      if (!scenario.submit || scenario.failCreation) {
        router.pop();
        await tester.pumpAndSettle();
      }
      if (scenario.throughMyItems) {
        expect(find.text('อุปกรณ์ของฉัน'), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();
      }

      final created = scenario.submit && !scenario.failCreation;
      expect(
        find.byKey(const ValueKey('shopee-card-1')),
        created ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('กล้องที่เพิ่งเพิ่ม'),
        created ? findsOneWidget : findsNothing,
      );
      expect(repository.cacheClearCount, created ? 1 : 0);
    });
  }
}
