import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/domain/entities/feed_item.dart';
import 'package:frontend/features/home/domain/repositories/home_repository.dart';
import 'package:frontend/features/home/presentation/pages/equipment_search_screen.dart';
import 'package:frontend/features/home/presentation/widgets/shopee_product_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({
    this.curatedItems = const [],
    this.nearbyItems = const [],
  });

  final List<FeedItem> curatedItems;
  final List<FeedItem> nearbyItems;

  @override
  void clearCache() {}

  @override
  Future<List<FeedCategory>> getCategories() async => const [];

  @override
  Future<List<FeedItem>> getCuratedItems() async => curatedItems;

  @override
  Future<List<FeedItem>> getNearbyItems({
    String? categoryId,
    String? searchQuery,
    int? minPrice,
    int? maxPrice,
    double? minRating,
  }) async {
    if (searchQuery == null || searchQuery.isEmpty) {
      return nearbyItems;
    }
    return nearbyItems.where((item) {
      return item.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Future<bool> toggleFavorite(String itemId) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<FeedItem> dummyCurated = [
    const FeedItem(
      id: '1',
      title: 'MacBook Air M2 13 นิ้ว',
      categoryId: 'computer',
      price: 650,
      priceUnit: '/ วัน',
      distanceKm: 0.8,
      imageUrl: '',
      rating: 4.9,
      reviewCount: 15,
      ownerName: 'chn.benmat',
      isVerified: true,
    ),
    const FeedItem(
      id: '2',
      title: 'กีตาร์โปร่ง Yamaha F310',
      categoryId: 'audio',
      price: 250,
      priceUnit: '/ วัน',
      distanceKm: 1.4,
      imageUrl: '',
      rating: 4.8,
      reviewCount: 8,
      ownerName: 'testuser',
      isVerified: true,
    ),
  ];

  final List<FeedItem> dummySearchable = [
    const FeedItem(
      id: '1',
      title: 'MacBook Air M2 13 นิ้ว',
      categoryId: 'computer',
      price: 650,
      priceUnit: '/ วัน',
      distanceKm: 0.8,
      imageUrl: '',
      rating: 4.9,
      reviewCount: 15,
      ownerName: 'chn.benmat',
      isVerified: true,
    ),
    const FeedItem(
      id: '3',
      title: 'เต็นท์แคมป์ปิ้ง Naturehike',
      categoryId: 'outdoor',
      price: 200,
      priceUnit: '/ วัน',
      distanceKm: 3.2,
      imageUrl: '',
      rating: 5.0,
      reviewCount: 3,
      ownerName: 'camper',
      isVerified: false,
    ),
    const FeedItem(
      id: '4',
      title: 'กล้อง Sony A7 IV',
      categoryId: 'camera',
      price: 850,
      priceUnit: '/ วัน',
      distanceKm: 1.0,
      imageUrl: '',
      rating: 4.9,
      reviewCount: 20,
      ownerName: 'photoman',
      isVerified: true,
    ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'equipment_recent_searches_v1': ['กล้อง Sony', 'ไมค์ไวเลส'],
    });
  });

  testWidgets(
      'Pre-Search: shows search bar, recent search tags, and curated item cards without filtering immediately',
      (tester) async {
    final fakeRepo = _FakeHomeRepository(
      curatedItems: dummyCurated,
      nearbyItems: dummySearchable,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentSearchScreen(
          homeRepository: fakeRepo,
          initialCuratedItems: dummyCurated,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. ตรวจสอบ Search Bar ด้านบน
    expect(find.byKey(const ValueKey('equipment-search-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-submit-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-back-button')), findsOneWidget);

    // 2. ตรวจสอบคำค้นหาเก่า (ประวัติการค้นหา)
    expect(find.text('ประวัติการค้นหา'), findsOneWidget);
    expect(find.text('กล้อง Sony'), findsOneWidget);
    expect(find.text('ไมค์ไวเลส'), findsOneWidget);
    expect(find.byKey(const ValueKey('clear-all-recent-searches')), findsOneWidget);

    // 3. ตรวจสอบสิ่งที่ผู้เช่าสนใจ (ต้องเป็นการ์ดสินค้าจริง ShopeeProductCard ไม่ใช่แค่หมวดหมู่)
    expect(find.text('สิ่งที่คุณอาจสนใจ'), findsOneWidget);
    expect(find.byType(ShopeeProductCard), findsNWidgets(2));
    expect(find.text('MacBook Air M2 13 นิ้ว'), findsOneWidget);
    expect(find.text('กีตาร์โปร่ง Yamaha F310'), findsOneWidget);

    // 4. ทดสอบพิมพ์ข้อความ: ต้องไม่เปลี่ยนไปแสดงผลลัพธ์การค้นหาทันที (ไม่ใช่เสิร์ชแล้วขึ้นมาเลย)
    await tester.enterText(
        find.byKey(const ValueKey('equipment-search-input')), 'เต็นท์');
    await tester.pump();

    // ยังคงอยู่ในหน้าคำแนะนำ & ประวัติ ไม่ได้แสดงผลลัพธ์ค้นหาทันที
    expect(find.text('สิ่งที่คุณอาจสนใจ'), findsOneWidget);
    expect(find.text('ประวัติการค้นหา'), findsOneWidget);
    expect(find.text('เต็นท์แคมป์ปิ้ง Naturehike'), findsNothing);
  });

  testWidgets(
      'Search Results: shows searched items only when search is submitted',
      (tester) async {
    final fakeRepo = _FakeHomeRepository(
      curatedItems: dummyCurated,
      nearbyItems: dummySearchable,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentSearchScreen(
          homeRepository: fakeRepo,
          initialCuratedItems: dummyCurated,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // พิมพ์คำค้นหา
    await tester.enterText(
        find.byKey(const ValueKey('equipment-search-input')), 'เต็นท์');
    await tester.pump();

    // กดปุ่ม "ค้นหา"
    await tester.tap(find.byKey(const ValueKey('search-submit-button')));
    await tester.pumpAndSettle();

    // ตอนนี้ต้องแสดงผลการค้นหา และมีสินค้าที่ค้นหาเจอ
    expect(find.textContaining('ผลการค้นหาสำหรับ'), findsOneWidget);
    expect(find.textContaining('"เต็นท์"'), findsOneWidget);
    expect(find.text('เต็นท์แคมป์ปิ้ง Naturehike'), findsOneWidget);
    expect(find.text('กีตาร์โปร่ง Yamaha F310'), findsNothing);

    // เมื่อกดปุ่มกากบาทล้างคำค้นหา ต้องกลับมาหน้า Pre-Search
    await tester.tap(find.byKey(const ValueKey('search-clear-button')));
    await tester.pumpAndSettle();

    expect(find.text('สิ่งที่คุณอาจสนใจ'), findsOneWidget);
    expect(find.text('ประวัติการค้นหา'), findsOneWidget);
  });

  testWidgets('Tapping a recent search tag triggers search directly',
      (tester) async {
    final fakeRepo = _FakeHomeRepository(
      curatedItems: dummyCurated,
      nearbyItems: dummySearchable,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentSearchScreen(
          homeRepository: fakeRepo,
          initialCuratedItems: dummyCurated,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // แตะที่แท็กประวัติการค้นหา
    await tester.tap(find.text('กล้อง Sony'));
    await tester.pumpAndSettle();

    // ต้องเข้าสู่หน้าแสดงผลการค้นหาคำว่า กล้อง Sony
    expect(find.textContaining('ผลการค้นหาสำหรับ'), findsOneWidget);
    expect(find.textContaining('"กล้อง Sony"'), findsOneWidget);
    expect(find.text('กล้อง Sony A7 IV'), findsOneWidget);
  });

  testWidgets('initialQuery executes search immediately on open',
      (tester) async {
    final fakeRepo = _FakeHomeRepository(
      curatedItems: dummyCurated,
      nearbyItems: dummySearchable,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentSearchScreen(
          homeRepository: fakeRepo,
          initialQuery: 'กล้อง Sony',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify search bar input is pre-populated
    final searchInput = find.byKey(const ValueKey('equipment-search-input'));
    expect(tester.widget<TextField>(searchInput).controller?.text, 'กล้อง Sony');

    // Verify results are automatically displayed
    expect(find.textContaining('ผลการค้นหาสำหรับ'), findsOneWidget);
    expect(find.textContaining('"กล้อง Sony"'), findsOneWidget);
    expect(find.text('กล้อง Sony A7 IV'), findsOneWidget);
  });

  testWidgets('search results view includes category filter button and system',
      (tester) async {
    final fakeRepo = _FakeHomeRepository(
      curatedItems: dummyCurated,
      nearbyItems: dummySearchable,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentSearchScreen(
          homeRepository: fakeRepo,
          initialQuery: 'กล้อง Sony',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify filter button is present in search results header
    expect(find.byKey(const ValueKey('category-filter-button')), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);
  });
}
