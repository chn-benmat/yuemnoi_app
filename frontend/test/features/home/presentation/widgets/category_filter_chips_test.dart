import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/presentation/widgets/category_filter_chips.dart';

void main() {
  const testCategories = [
    FeedCategory(id: 'all', name: 'ทั้งหมด'),
    FeedCategory(id: 'camera', name: 'กล้องถ่ายภาพ'),
    FeedCategory(id: 'camping', name: 'แคมป์ปิ้ง'),
    FeedCategory(id: 'computer', name: 'คอมพิวเตอร์/ไอที'),
    FeedCategory(id: 'music', name: 'เครื่องดนตรี'),
    FeedCategory(id: 'gaming', name: 'เกม/บันเทิง'),
    FeedCategory(id: 'tools', name: 'อุปกรณ์ช่าง'),
    FeedCategory(id: 'audio', name: 'เครื่องเสียง'),
    FeedCategory(id: 'phone', name: 'โทรศัพท์/สื่อสาร'),
    FeedCategory(id: 'sports', name: 'กีฬา/ฟิตเนส'),
  ];

  testWidgets('renders all requested categories with icons', (tester) async {
    String selectedId = 'all';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: testCategories,
            selectedCategoryId: selectedId,
            onCategorySelected: (id) => selectedId = id,
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify presence of first few visible categories (all/ทั้งหมด is excluded)
    expect(find.text('ทั้งหมด'), findsNothing);
    expect(find.text('กล้องถ่ายภาพ'), findsOneWidget);
    expect(find.text('แคมป์ปิ้ง'), findsOneWidget);

    // Verify icons & assets
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('selected chip has white square tile and white label text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.primaryColor,
          body: CategoryFilterChips(
            categories: testCategories,
            selectedCategoryId: 'camera',
            onCategorySelected: _dummyCallback,
          ),
        ),
      ),
    );
    await tester.pump();

    final cameraChipFinder = find.byKey(const ValueKey('category-chip-camera'));
    expect(cameraChipFinder, findsOneWidget);

    final animatedContainer = tester.widget<AnimatedContainer>(
      find.descendant(
        of: cameraChipFinder,
        matching: find.byType(AnimatedContainer),
      ),
    );

    final boxDecoration = animatedContainer.decoration as BoxDecoration;
    expect(boxDecoration.color, Colors.white);

    final text = tester.widget<Text>(find.text('กล้องถ่ายภาพ'));
    expect(text.style?.color, Colors.white);
  });

  testWidgets('tapping a category triggers onCategorySelected callback', (
    tester,
  ) async {
    String? selectedId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: testCategories,
            selectedCategoryId: 'all',
            onCategorySelected: (id) => selectedId = id,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('กล้องถ่ายภาพ'));
    await tester.pump();

    expect(selectedId, 'camera');
  });

  testWidgets('horizontal scroll works smoothly on phone viewport', (
    tester,
  ) async {
    // Set a narrow phone screen size (360x640)
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: testCategories,
            selectedCategoryId: 'all',
            onCategorySelected: _dummyCallback,
          ),
        ),
      ),
    );
    await tester.pump();

    // Scroll horizontally to find the last item
    await tester.scrollUntilVisible(find.text('กีฬา/ฟิตเนส'), 80);
    await tester.pumpAndSettle();

    expect(find.text('กีฬา/ฟิตเนส'), findsOneWidget);
  });

  testWidgets('excludes appliances / เครื่องใช้ไฟฟ้า from chips', (
    tester,
  ) async {
    const categoriesWithAppliances = [
      ...testCategories,
      FeedCategory(
        id: 'appliances',
        name: 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: categoriesWithAppliances,
            selectedCategoryId: 'all',
            onCategorySelected: _dummyCallback,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('เครื่องใช้ไฟฟ้า'), findsNothing);
    expect(find.byIcon(Icons.kitchen_rounded), findsNothing);
  });

  testWidgets('excludes other / อื่นๆ from chips', (tester) async {
    const categoriesWithOther = [
      ...testCategories,
      FeedCategory(id: 'other', name: 'อื่น ๆ'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: categoriesWithOther,
            selectedCategoryId: 'all',
            onCategorySelected: _dummyCallback,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('อื่น ๆ'), findsNothing);
    expect(find.text('อื่นๆ'), findsNothing);
  });

  testWidgets('excludes general / ทั่วไป from chips', (tester) async {
    const categoriesWithGeneral = [
      ...testCategories,
      FeedCategory(id: 'general', name: 'ทั่วไป'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: categoriesWithGeneral,
            selectedCategoryId: 'all',
            onCategorySelected: _dummyCallback,
          ),
        ),
      ),
    );
    await tester.pump();
  });

  testWidgets('excludes all / ทั้งหมด from chips', (tester) async {
    const categoriesWithAll = [
      FeedCategory(id: 'all', name: 'ทั้งหมด'),
      ...testCategories,
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: categoriesWithAll,
            selectedCategoryId: 'camera',
            onCategorySelected: _dummyCallback,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ทั้งหมด'), findsNothing);
    expect(find.byKey(const ValueKey('category-chip-all')), findsNothing);
  });

  testWidgets('categories use configured asset icons and fallback icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryFilterChips(
            categories: testCategories,
            selectedCategoryId: 'all',
            onCategorySelected: _dummyCallback,
          ),
        ),
      ),
    );
    await tester.pump();

    void expectChipAsset(String categoryId, String expectedAsset) {
      final chipFinder = find.byKey(ValueKey('category-chip-$categoryId'));
      expect(chipFinder, findsOneWidget);
      final imageFinder = find.descendant(
        of: chipFinder,
        matching: find.byType(Image),
      );
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect((imageWidget.image as AssetImage).assetName, expectedAsset);
    }

    expectChipAsset('camera', 'assets/icons/camera.png');
    expectChipAsset('camping', 'assets/icons/tent.png');
    expectChipAsset('computer', 'assets/icons/computer.png');
    expectChipAsset('music', 'assets/icons/guitar.png');
    expectChipAsset('gaming', 'assets/icons/joystick.png');
    expectChipAsset('tools', 'assets/icons/drill.png');
    expectChipAsset('audio', 'assets/icons/audio.png');
    expectChipAsset('phone', 'assets/icons/phone.png');
    expectChipAsset('sports', 'assets/icons/dumbell.png');
  });
}

void _dummyCallback(String id) {}
