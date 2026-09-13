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
    expect(find.byType(SkeletonShimmer), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNWidgets(30));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
