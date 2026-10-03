import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/custom_bottom_navbar.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

void main() {
  group('NotificationPage UI Tests', () {
    testWidgets('renders NotificationPage with two distinct sections, ดูทั้งหมด, and อ่านทั้งหมด', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: NotificationPage()));
      await tester.pumpAndSettle();

      expect(find.text('การแจ้งเตือน'), findsOneWidget);
      expect(find.text('สถานะอุปกรณ์'), findsOneWidget);
      expect(find.text('อัปเดตและข้อความระบบ'), findsOneWidget);
      expect(find.text('ยินดีต้อนรับสู่ Yuemnoi'), findsOneWidget);
      expect(find.text('การชำระเงินปลอดภัย'), findsOneWidget);

      // หมวดสถานะอุปกรณ์แสดงปุ่ม "ดูทั้งหมด"
      expect(find.text('ดูทั้งหมด'), findsOneWidget);
      // หมวดข้อความระบบแสดงปุ่ม "อ่านทั้งหมด"
      expect(find.text('อ่านทั้งหมด'), findsOneWidget);

      // ไม่มีปุ่มรกรุงรังภายในตัวการ์ดอุปกรณ์
      expect(find.text('ส่งคืนอุปกรณ์'), findsNothing);
      expect(find.text('ดูรายละเอียด'), findsNothing);
    });

    testWidgets('tap system mark all as read triggers feedback snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: NotificationPage()));
      await tester.pumpAndSettle();

      // แตะปุ่ม "อ่านทั้งหมด" ของหมวดข้อความระบบ
      await tester.tap(find.text('อ่านทั้งหมด'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('ทำเครื่องหมายอ่านแล้ว'), findsOneWidget);
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
