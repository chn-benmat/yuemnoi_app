import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/domain/entities/feed_category.dart';
import 'package:frontend/features/home/presentation/widgets/category_filter_sheet.dart';

void main() {
  const testCategories = [
    FeedCategory(id: 'all', name: 'ทั้งหมด'),
    FeedCategory(id: 'camera', name: 'กล้องและอุปกรณ์ถ่ายภาพ'),
    FeedCategory(id: 'audio', name: 'เครื่องเสียง'),
    FeedCategory(id: 'camping', name: 'แคมป์ปิ้ง'),
  ];

  testWidgets('CategoryFilterButton opens Single Page Scroll filter and applies selection', (
    tester,
  ) async {
    String appliedCategory = '';
    int? appliedMinPrice;
    int? appliedMaxPrice;
    double? appliedMinRating;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CategoryFilterButton(
              categories: testCategories,
              selectedCategoryId: 'all',
              onApplyFilter: ({
                required String categoryId,
                int? minPrice,
                int? maxPrice,
                double? minRating,
              }) {
                appliedCategory = categoryId;
                appliedMinPrice = minPrice;
                appliedMaxPrice = maxPrice;
                appliedMinRating = minRating;
              },
              onResetFilter: () {},
            ),
          ),
        ),
      ),
    );

    // 1. ตรวจสอบปุ่มตัวกรอง
    final filterBtn = find.byKey(const ValueKey('category-filter-button'));
    expect(filterBtn, findsOneWidget);

    // 2. กดเปิด Modal ตัวกรอง
    await tester.tap(filterBtn);
    await tester.pumpAndSettle();

    // 3. ตรวจสอบว่ามีทั้ง 3 ส่วนแสดงผลในหน้าเดียวกัน (Single Page)
    expect(find.text('ตัวกรองสินค้า'), findsOneWidget);
    expect(find.text('ช่วงราคาเช่าต่อวัน (฿)'), findsOneWidget);
    expect(find.text('หมวดหมู่อุปกรณ์'), findsOneWidget);
    expect(find.text('คะแนนรีวิว'), findsOneWidget);

    // ตรวจสอบว่าไม่มี Sidebar tab อีกต่อไป
    expect(find.byKey(const ValueKey('sidebar-tab-0')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-tab-1')), findsNothing);

    // 4. เลือกหมวดหมู่ 'กล้องและอุปกรณ์ถ่ายภาพ'
    final cameraChip = find.byKey(const ValueKey('filter-category-item-camera'));
    expect(cameraChip, findsOneWidget);
    await tester.tap(cameraChip);
    await tester.pumpAndSettle();

    // 5. เลือกช่วงราคาลัด 'ไม่เกิน 500 ฿'
    final preset500 = find.text('ไม่เกิน 500 ฿');
    expect(preset500, findsOneWidget);
    await tester.tap(preset500);
    await tester.pumpAndSettle();

    // 6. เลื่อนเพื่อกดคะแนนรีวิว 4 ดาวขึ้นไป
    final rating4Opt = find.text('4 ดาวขึ้นไป');
    await tester.ensureVisible(rating4Opt);
    await tester.tap(rating4Opt);
    await tester.pumpAndSettle();

    // ตรวจสอบ Badge บนปุ่มนำไปใช้แสดงจำนวน 3 ตัวกรอง
    expect(find.text('นำไปใช้ (3)'), findsOneWidget);

    // 7. กดปุ่ม 'นำไปใช้'
    final applyBtn = find.byKey(const ValueKey('apply-filter-modal-button'));
    await tester.ensureVisible(applyBtn);
    await tester.tap(applyBtn);
    await tester.pumpAndSettle();

    // 8. ตรวจสอบว่า Callback ได้รับค่าที่เลือกถูกต้อง
    expect(appliedCategory, 'camera');
    expect(appliedMinPrice, 1);
    expect(appliedMaxPrice, 500);
    expect(appliedMinRating, 4.0);
  });
}
