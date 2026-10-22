import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/app_notification_service.dart';
import 'package:frontend/core/widgets/custom_bottom_navbar.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

import 'support/fake_notification_repository.dart';

void main() {
  group('NotificationPage UI Tests', () {
    testWidgets(
      'loading keeps all section headings at their empty inbox positions',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final response = Completer<NotificationInboxPage>();
        final repository = FakeNotificationRepository()
          ..onGet = (_, _) => response.future;
        final service = AppNotificationService(repository: repository);
        addTearDown(service.dispose);
        service.setSession('alice');
        await tester.pumpWidget(
          MaterialApp(home: NotificationPage(service: service)),
        );
        await tester.pump();

        const headings = ['สถานะอุปกรณ์', 'อัปเดตและข้อความระบบ'];
        final loadingPositions = [
          for (final heading in headings) tester.getTopLeft(find.text(heading)),
        ];
        expect(find.byType(SkeletonShimmer), findsNWidgets(2));

        response.complete(inboxPage([]));
        await tester.pumpAndSettle();
        for (var index = 0; index < headings.length; index++) {
          expect(
            loadingPositions[index],
            tester.getTopLeft(find.text(headings[index])),
            reason: '${headings[index]} must not jump after loading',
          );
        }
        expect(find.byType(SkeletonShimmer), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        service.dispose();
      },
    );

    testWidgets('renders rental and app history without chat notifications', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = FakeNotificationRepository()
        ..page = inboxPage([
          notification(
            id: 'rental',
            category: AppNotificationCategory.rental,
            title: 'รายการเช่ายืนยันแล้ว',
          ),
          notification(
            id: 'chat',
            category: AppNotificationCategory.chat,
            conversationId: 'room',
            unreadCount: 3,
            title: 'ข้อความล่าสุดจากสมชาย',
          ),
          notification(id: 'app', title: 'ยืนยันตัวตนสำเร็จ'),
        ]);
      final service = AppNotificationService(repository: repository);
      addTearDown(service.dispose);
      service.setSession('alice');
      await service.refresh();
      await tester.pumpWidget(
        MaterialApp(home: NotificationPage(service: service)),
      );
      await tester.pumpAndSettle();

      expect(find.text('การแจ้งเตือน'), findsOneWidget);
      expect(find.text('สถานะอุปกรณ์'), findsOneWidget);
      expect(find.text('ข้อความแชต'), findsNothing);
      expect(
        find.text('ข้อความล่าสุดและจำนวนที่ยังไม่อ่านในแต่ละห้อง'),
        findsNothing,
      );
      expect(find.text('อัปเดตและข้อความระบบ'), findsOneWidget);
      expect(find.text('ยินดีต้อนรับสู่ Yuemnoi'), findsNothing);
      expect(find.text('การชำระเงินปลอดภัย'), findsNothing);
      expect(find.text('รายการเช่ายืนยันแล้ว'), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-chat')), findsNothing);
      expect(find.text('ข้อความล่าสุดจากสมชาย'), findsNothing);
      expect(find.text('3 ข้อความที่ยังไม่อ่าน'), findsNothing);
      expect(find.text('ยืนยันตัวตนสำเร็จ'), findsOneWidget);
      expect(find.text('อ่านทั้งหมด'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });

    testWidgets('mark all persists read state and updates unread badge', (
      tester,
    ) async {
      final repository = FakeNotificationRepository()
        ..page = inboxPage([notification(id: 'app')]);
      final service = AppNotificationService(repository: repository);
      addTearDown(service.dispose);
      service.setSession('alice');
      await service.refresh();
      await tester.pumpWidget(
        MaterialApp(home: NotificationPage(service: service)),
      );
      await tester.pumpAndSettle();
      expect(service.inbox.value.unreadCount, 1);
      await tester.tap(find.text('อ่านทั้งหมด'));
      await tester.pumpAndSettle();
      expect(service.inbox.value.unreadCount, 0);
      expect(find.textContaining('ทำเครื่องหมายอ่านแล้ว'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });

    testWidgets('guest sees sign-in message and no private history', (
      tester,
    ) async {
      final service = AppNotificationService(
        repository: FakeNotificationRepository(),
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(home: NotificationPage(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('เข้าสู่ระบบเพื่อดูการแจ้งเตือน'), findsOneWidget);
      expect(
        find.text('สถานะการเช่าและข้อมูลบัญชีจะแสดงที่นี่'),
        findsOneWidget,
      );
      expect(find.text('การชำระเงินปลอดภัย'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  });

  group('CustomBottomNavbar with Notification Tab', () {
    testWidgets('renders current 4 tabs including Notification tab', (
      tester,
    ) async {
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
