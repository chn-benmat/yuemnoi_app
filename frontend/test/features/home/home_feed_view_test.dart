import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _FakeHomeRepository implements HomeRepository {
  @override
  void clearCache() {}

  @override
  Future<List<FeedCategory>> getCategories() async => const [
    FeedCategory(id: 'all', name: 'ทั้งหมด'),
    FeedCategory(id: 'camera', name: 'กล้องถ่ายภาพ'),
    FeedCategory(id: 'camping', name: 'แคมป์ปิ้ง'),
  ];

  @override
  Future<List<FeedItem>> getCuratedItems() async => List.generate(
    10,
    (i) => FeedItem(
      id: '$i',
      title: switch (i) {
        0 => 'โต๊ะ',
        1 => 'อุปกรณ์ทดสอบ 1 สำหรับถ่ายภาพและงานวิดีโอ',
        _ => 'อุปกรณ์ทดสอบ $i',
      },
      categoryId: 'camera',
      price: i == 0 ? 75 : 200 + i * 50,
      priceUnit: i == 0 ? '/ ชั่วโมง' : '/วัน',
      rating: 4.8,
      reviewCount: 12,
      paidBookingCount: switch (i) {
        0 => 3,
        1 => 1,
        _ => 0,
      },
      isRentalOccupied: i == 1,
      distanceKm: 1.5,
      isVerified: true,
      ownerName: 'ผู้ให้เช่า',
      locationName: i == 0 ? 'ซีคอน บางแค' : 'กรุงเทพฯ',
      imageUrl: '',
    ),
  );

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
  testWidgets(
    'search bar and category chips stay fixed while products scroll',
    (tester) async {
      final repository = _FakeHomeRepository();
      final bloc = HomeBloc(
        getHomeFeed: GetHomeFeedUseCase(repository),
        homeRepository: repository,
      )..add(const LoadHomeFeedStarted());
      addTearDown(bloc.close);

      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<HomeBloc>.value(
            value: bloc,
            child: const HomeFeedView(),
          ),
        ),
      );

      // Initial load
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Both search bar and chips are visible
      expect(find.byType(HomeSearchBar), findsOneWidget);
      expect(find.byType(CategoryFilterChips), findsOneWidget);
      final price = find.text('฿75');
      final location = find.text('ซีคอน บางแค');
      final count = find.text('เช่าแล้ว 3 ครั้ง');
      expect(price, findsOneWidget);
      expect(location, findsOneWidget);
      expect(count, findsOneWidget);
      expect(find.text('฿250'), findsOneWidget);
      final occupied = find.text('กำลังถูกเช่า');
      final occupiedCount = find.text('เช่าแล้ว 1 ครั้ง');
      expect(occupied, findsOneWidget);
      expect(occupiedCount, findsOneWidget);
      expect(find.textContaining('เช่าแล้ว'), findsNWidgets(2));
      expect(find.textContaining('เริ่มต้น'), findsNothing);
      expect(find.textContaining('ชั่วโมง'), findsNothing);
      expect(find.textContaining('/วัน'), findsNothing);
      expect(find.textContaining('กม.'), findsNothing);
      expect(find.text('ผู้ให้เช่า'), findsNothing);
      final title = find.text('โต๊ะ');
      final priceRect = tester.getRect(price);
      expect(
        priceRect.top - tester.getRect(title).bottom,
        inInclusiveRange(4, 8),
      );
      expect(tester.getTopLeft(location).dy, greaterThan(priceRect.bottom));
      expect(tester.getTopLeft(count).dx, greaterThan(priceRect.right));
      expect(tester.getCenter(count).dy, closeTo(priceRect.center.dy, 1));
      final firstCard = find.byKey(const ValueKey('shopee-card-0'));
      final secondCard = find.byKey(const ValueKey('shopee-card-1'));
      final firstCardRect = tester.getRect(firstCard);
      final secondCardRect = tester.getRect(secondCard);
      expect(secondCardRect.right - tester.getRect(occupied).right, 10);
      expect(
        tester.getRect(occupied).bottom,
        lessThan(tester.getRect(occupiedCount).top),
      );
      final secondLocation = find.descendant(
        of: secondCard,
        matching: find.text('กรุงเทพฯ'),
      );
      expect(firstCardRect.bottom - tester.getRect(location).bottom, 10);
      expect(secondCardRect.bottom - tester.getRect(secondLocation).bottom, 10);
      expect(firstCardRect.top, secondCardRect.top);
      expect(secondCardRect.height, greaterThan(firstCardRect.height));

      final initialSearchBarPosition = tester.getTopLeft(
        find.byType(HomeSearchBar),
      );
      final initialChipPosition = tester.getTopLeft(
        find.byType(CategoryFilterChips),
      );

      // Scroll down by 40px
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pumpAndSettle();

      // 1. Search bar stays fixed at the exact same position (does not scroll)
      final afterScrollSearchBarPosition = tester.getTopLeft(
        find.byType(HomeSearchBar),
      );
      expect(
        afterScrollSearchBarPosition.dy,
        equals(initialSearchBarPosition.dy),
      );

      // 2. Category chips stay pinned with the search bar.
      final afterScrollChipPosition = tester.getTopLeft(
        find.byType(CategoryFilterChips),
      );
      expect(afterScrollChipPosition.dy, equals(initialChipPosition.dy));
    },
  );

  testWidgets(
    'tapping category chip opens search and keeps home feed normal on return',
    (tester) async {
      final repository = _FakeHomeRepository();
      final bloc = HomeBloc(
        getHomeFeed: GetHomeFeedUseCase(repository),
        homeRepository: repository,
      )..add(const LoadHomeFeedStarted());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<HomeBloc>.value(
            value: bloc,
            child: const HomeFeedView(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initially search bar is empty and category is all
      final searchTextField = find.byKey(const ValueKey('home-search-field'));
      expect(tester.widget<TextField>(searchTextField).controller?.text, '');
      expect((bloc.state as HomeLoaded).selectedCategoryId, 'all');

      // Tap 'กล้องถ่ายภาพ' chip
      await tester.tap(find.text('กล้องถ่ายภาพ'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Home feed remains in normal state ('all') so returning from search shows diverse items
      expect(tester.widget<TextField>(searchTextField).controller?.text, '');
      expect(bloc.state is HomeLoaded, isTrue);
      expect((bloc.state as HomeLoaded).selectedCategoryId, 'all');
    },
  );

  testWidgets(
    'control deck displays favorites heart button instead of filter button',
    (tester) async {
      final repository = _FakeHomeRepository();
      final bloc = HomeBloc(
        getHomeFeed: GetHomeFeedUseCase(repository),
        homeRepository: repository,
      )..add(const LoadHomeFeedStarted());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<HomeBloc>.value(
            value: bloc,
            child: const HomeFeedView(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Favorites heart button is present in control deck
      expect(
        find.byKey(const ValueKey('home-favorites-button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      // Old filter button is NOT in control deck
      expect(
        find.byKey(const ValueKey('category-filter-button')),
        findsNothing,
      );
    },
  );
}
