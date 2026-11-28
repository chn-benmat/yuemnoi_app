import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/profile/presentation/widgets/items/my_items_widgets.dart';

void main() {
  testWidgets('shows item-card skeletons without a progress indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MyItemsLoadingSkeleton())),
    );

    expect(find.byKey(const ValueKey('my-items-skeleton')), findsOneWidget);
    expect(find.byType(SkeletonShimmer), findsWidgets);
    expect(find.byType(SkeletonBox), findsNWidgets(27));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows no skeleton when the owner had no items last time', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MyItemsLoadingSkeleton(count: 0))),
    );

    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.byType(SkeletonShimmer), findsNothing);
  });

  testWidgets('shows one card per item from the last load', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MyItemsLoadingSkeleton(count: 2))),
    );

    // แถวหัว 2 ชิ้น และการ์ดละ 5 ชิ้น
    expect(find.byType(SkeletonBox), findsNWidgets(12));
  });
}
