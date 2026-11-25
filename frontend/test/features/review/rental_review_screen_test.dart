import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/features/profile/data/datasources/profile_storefront_remote_data_source.dart';
import 'package:frontend/features/review/presentation/pages/rental_review_screen.dart';

class OwnerProfileSource extends ProfileStorefrontRemoteDataSource {
  String? requestedId;
  bool fail = false;

  @override
  Future<Map<String, dynamic>> getIdentity(String userId) async {
    requestedId = userId;
    if (fail) throw Exception('offline');
    return {'user_image_url': 'https://example.test/owner.png'};
  }
}

void main() {
  testWidgets('the review route prefills the rating and it remains editable', (
    tester,
  ) async {
    final router = AppRoutes.createRouter(
      initialLocation: AppRoutes.review,
      initialExtra: {'initialRating': 4},
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('เป็นประสบการณ์ที่ดีมาก ประทับใจ 😊'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.star_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('เป็นประสบการณ์ที่ไม่น่าประทับใจ 😞'), findsOneWidget);
  });

  testWidgets('loads the lender avatar using the lender ID', (tester) async {
    final source = OwnerProfileSource();
    await tester.pumpWidget(
      MaterialApp(
        home: RentalReviewScreen(ownerId: 'lender-id', profileSource: source),
      ),
    );
    await tester.pump();
    expect(source.requestedId, 'lender-id');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://example.test/owner.png',
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the fallback avatar when the profile cannot load', (
    tester,
  ) async {
    final source = OwnerProfileSource()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RentalReviewScreen(ownerId: 'lender-id', profileSource: source),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.image(const AssetImage('assets/images/user.png')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
