import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app.dart';
import 'package:frontend/core/navigation/app_routes.dart';
import 'package:frontend/core/widgets/custom_bottom_navbar.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

void main() {
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

  testWidgets(
    'the home tab opens the notification maintenance screen on demand',
    (tester) async {
      dotenv.loadFromString(envString: 'API_URL=https://api.example.com');
      await tester.pumpWidget(const YuemnoiApp(initialRoute: AppRoutes.home));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NotificationPage), findsNothing);

      await tester.tap(find.byKey(const ValueKey('nav-notification')));
      await tester.pump();
      expect(find.byType(NotificationPage), findsOneWidget);
      expect(find.text('ระบบแจ้งเตือนกำลังปรับปรุง'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pump();
      expect(find.byType(NotificationPage, skipOffstage: false), findsNothing);
    },
  );
}
