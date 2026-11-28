import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/product_listing_card.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_list_loading_skeleton.dart';
import 'package:frontend/features/profile/presentation/widgets/items/favorite_widgets.dart';
import 'package:frontend/features/profile/presentation/widgets/profile/user_profile_widgets.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_history_widgets.dart';

void main() {
  testWidgets('product card placeholders shimmer over a white card', (
    tester,
  ) async {
    const cardKey = ValueKey('product-card');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: cardKey,
            child: SizedBox(width: 200, child: ProductCardSkeleton()),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(cardKey),
    );

    final first = boundary.toImageSync();
    await tester.pump(const Duration(milliseconds: 700));
    final second = boundary.toImageSync();

    await tester.runAsync(() async {
      try {
        final firstPixels = (await first.toByteData())!;
        final secondPixels = (await second.toByteData())!;
        final photoPixel = (100 * first.width + 100) * 4;
        final cardPixel = (220 * first.width + 185) * 4;

        expect(firstPixels.getUint32(cardPixel), 0xFFFFFFFF);
        expect(secondPixels.getUint32(cardPixel), 0xFFFFFFFF);
        expect(
          secondPixels.getUint32(photoPixel),
          isNot(firstPixels.getUint32(photoPixel)),
        );
      } finally {
        first.dispose();
        second.dispose();
      }
    });
  });

  final cases = <String, Widget>{
    'favorite': const FavoriteLoadingSkeleton(),
    'rental history': const RentalHistoryLoadingSkeleton(),
    'user profile': const UserProfileLoadingSkeleton(),
    'chat list': const ChatListLoadingSkeleton(),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key} loading uses a skeleton instead of a spinner', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: entry.value)));

      expect(find.byType(SkeletonShimmer), findsWidgets);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }
}
