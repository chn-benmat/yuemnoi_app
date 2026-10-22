import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/domain/entities/profile_storefront.dart';
import 'package:frontend/features/profile/domain/usecases/get_profile_storefront_usecase.dart';
import 'package:frontend/features/profile/presentation/pages/profile/user_profile_view_screen.dart';
import 'package:frontend/features/profile/presentation/widgets/profile/user_profile_widgets.dart';

import '../../domain/usecases/get_profile_storefront_usecase_test.dart';

void main() {
  testWidgets('visitor opens public reviewer names and comments from rating', (
    tester,
  ) async {
    final repository = FakeStorefrontRepository()
      ..reviews = [
        const StorefrontReview(
          itemId: 1,
          rating: 5,
          reviewerName: 'ผู้รีวิวกล้อง',
          description: 'เจ้าของใจดี อุปกรณ์สะอาด',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileViewScreen(
          args: const UserProfileViewArgs(
            userId: 'owner',
            displayName: 'เจ้าของ',
          ),
          getStorefront: GetProfileStorefrontUseCase(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-reviews')));
    await tester.pumpAndSettle();
    expect(find.text('ผู้รีวิวกล้อง'), findsOneWidget);
    expect(find.text('เจ้าของใจดี อุปกรณ์สะอาด'), findsOneWidget);
    expect(find.text('อุปกรณ์: กล้องตัวแรก'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final own in [true, false]) {
    testWidgets('rating is tappable for owner=$own including no reviews', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserProfileHeaderSection(
              displayName: 'เจ้าของ',
              avatarUrl: null,
              bio: null,
              reviews: const ReviewSummary(),
              isVerified: false,
              isCurrentUser: own,
              onEditProfile: () {},
              onReviewsTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('profile-reviews')));
      expect(taps, 1);
    });
  }

  testWidgets('owner can edit next to identity; visitor does not see edit', (
    tester,
  ) async {
    var edits = 0;
    Widget header(bool own) => MaterialApp(
      home: Scaffold(
        body: UserProfileHeaderSection(
          displayName: 'ชื่อเจ้าของอุปกรณ์',
          avatarUrl: null,
          bio: null,
          reviews: const ReviewSummary(),
          isVerified: true,
          isCurrentUser: own,
          onEditProfile: () => edits++,
        ),
      ),
    );
    await tester.pumpWidget(header(true));
    await tester.tap(find.byKey(const ValueKey('edit-storefront-profile')));
    expect(edits, 1);
    expect(find.text('ยังไม่มีรีวิว'), findsOneWidget);
    expect(find.text('ยืนยันตัวตนแล้ว'), findsOneWidget);
    await tester.pumpWidget(header(false));
    expect(find.byKey(const ValueKey('edit-storefront-profile')), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'visitor inventory and sticky chat fit 320px at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakeStorefrontRepository()
          ..identity = const StorefrontIdentity(
            displayName: 'ชื่อเจ้าของอุปกรณ์ที่ยาวมากเพื่อทดสอบการแสดงผล',
            isVerified: true,
          );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: UserProfileViewScreen(
              args: const UserProfileViewArgs(
                userId: 'owner',
                displayName: 'ชื่อเจ้าของที่ยาวมากเพื่อทดสอบการแสดงผล',
              ),
              getStorefront: GetProfileStorefrontUseCase(repository),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('storefront-chat')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('edit-storefront-profile')),
          findsNothing,
        );
        await tester.scrollUntilVisible(find.textContaining('ชั่วโมง'), 150);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('ชั่วโมง'), findsOneWidget);
        expect(find.text('กำลังถูกเช่า'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('storefront-chat')));
        await tester.pumpAndSettle();
        expect(find.text('เข้าสู่ระบบเพื่อใช้งานแชท'), findsOneWidget);
        await tester.tap(find.text('ไว้ทีหลัง'));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'failed inventory offers retry and does not claim empty inventory',
    (tester) async {
      final repository = FakeStorefrontRepository()..failItems = true;
      await tester.pumpWidget(
        MaterialApp(
          home: UserProfileViewScreen(
            args: const UserProfileViewArgs(
              userId: 'owner',
              displayName: 'เจ้าของ',
            ),
            getStorefront: GetProfileStorefrontUseCase(repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีอุปกรณ์ให้เช่า'), findsNothing);
      expect(find.text('ยังแสดงอุปกรณ์ไม่ได้'), findsOneWidget);
      repository.failItems = false;
      await tester.tap(find.text('ลองใหม่').last);
      await tester.pumpAndSettle();
      expect(find.byType(UserProfileRentalCard), findsNWidgets(2));
    },
  );
}
