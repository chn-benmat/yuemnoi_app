import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/widgets/custom_bottom_navbar.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

void main() {
  testWidgets('only the selected tab uses purple for its icon and label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CustomBottomNavbar(
            selectedIndex: 0,
            onTabChange: (_) {},
          ),
        ),
      ),
    );

    final icons = tester.widgetList<Icon>(find.byType(Icon));
    final labels = tester.widgetList<Text>(find.byType(Text));
    const inactiveColor = Color(0xFF64748B);
    const expectedColors = [
      AppColors.primaryColor,
      inactiveColor,
      inactiveColor,
      inactiveColor,
    ];
    expect(icons.map((icon) => icon.color), expectedColors);
    expect(labels.map((label) => label.style?.color), expectedColors);
  });

  testWidgets('navbar keeps the notification tab and only badges chat', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CustomBottomNavbar(
            selectedIndex: 0,
            hasUnreadChat: true,
            onTabChange: (index) => selected = index,
          ),
        ),
      ),
    );

    final notifications = find.byKey(const ValueKey('nav-notification'));
    expect(notifications, findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification-unread-badge')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('chat-unread-badge')), findsOneWidget);
    await tester.tap(notifications);
    expect(selected, 2);
    await tester.tap(find.byKey(const ValueKey('nav-profile')));
    expect(selected, 3);
  });

  testWidgets('notification tab shows a red dot when there is something new', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CustomBottomNavbar(
            selectedIndex: 0,
            hasNewNotification: true,
            onTabChange: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('notification-unread-badge')),
      findsOneWidget,
    );
  });

  testWidgets(
    'the notification page is mounted only while its bottom tab is selected',
    (tester) async {
      dotenv.loadFromString(envString: 'API_URL=https://api.example.com');
      await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NotificationPage), findsNothing);

      await tester.tap(find.byKey(const ValueKey('nav-notification')));
      await tester.pump();
      expect(find.byType(NotificationPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pump();
      expect(find.byType(NotificationPage, skipOffstage: false), findsNothing);
    },
  );
}
