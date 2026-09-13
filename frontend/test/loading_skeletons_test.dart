import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/chat/presentation/widgets/chat_list_loading_skeleton.dart';
import 'package:frontend/features/profile/presentation/widgets/items/favorite_widgets.dart';
import 'package:frontend/features/profile/presentation/widgets/profile/user_profile_widgets.dart';
import 'package:frontend/features/profile/presentation/widgets/rentals/rental_history_widgets.dart';

void main() {
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

      expect(find.byType(SkeletonShimmer), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }
}
