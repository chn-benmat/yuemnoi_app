import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/custom_bottom_navbar.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

void main() {
  group('NotificationPage UI Tests', () {
    testWidgets('renders NotificationPage header and filter tabs properly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NotificationPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('การแจ้งเตือน'), findsOneWidget);
      expect(find.text('ทั้งหมด'), findsOneWidget);
      expect(find.text('ระบบ (2)'), findsOneWidget);
      expect(find.text('ยินดีต้อนรับสู่ Yuemnoi'), findsOneWidget);
      expect(find.text('การชำระเงินปลอดภัย'), findsOneWidget);
    });

    testWidgets('filtering by system shows system notifications', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NotificationPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ระบบ (2)'));
      await tester.pumpAndSettle();

      expect(find.text('ยินดีต้อนรับสู่ Yuemnoi'), findsOneWidget);
    });
  });

  group('CustomBottomNavbar with Notification Tab', () {
    testWidgets('renders 5 tabs including Notification tab', (tester) async {
      int tappedIndex = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CustomBottomNavbar(
              selectedIndex: 0,
              onTabChange: (index) => tappedIndex = index,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-chat')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-notification')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-wallet')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-profile')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-notification')));
      await tester.pumpAndSettle();
      expect(tappedIndex, 2);
    });

    testWidgets(
      'renders notification unread badge when hasUnreadNotification is true',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: CustomBottomNavbar(
                selectedIndex: 0,
                hasUnreadNotification: true,
                onTabChange: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('notification-unread-badge')),
          findsWidgets,
        );
      },
    );
  });
}
