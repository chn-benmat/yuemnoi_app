import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/app_notification_service.dart';
import 'package:frontend/core/widgets/skeleton_shimmer.dart';
import 'package:frontend/features/notification/presentation/pages/page.dart';

import 'support/fake_notification_repository.dart';

void main() {
  group('NotificationPage UI Tests', () {
    testWidgets('history loads on demand and has no foreground alerts', (
      tester,
    ) async {
      final repository = FakeNotificationRepository();
      final history = AppNotificationService.history(repository: repository);
      addTearDown(history.dispose);
      final alerts = <AppNotification>[];
      history.foregroundEvents.listen(alerts.add);

      history.setSession('alice');
      await history.refresh();
      expect(repository.offsets, [0]);
      repository.page = inboxPage([
        notification(
          id: 'rental',
          category: AppNotificationCategory.rental,
          second: 2,
        ),
      ], second: 3);
      await tester.pump(const Duration(minutes: 2));
      await history.handlePush({'notification_id': 'rental'});
      expect(repository.offsets, [0]);
      expect(history.inbox.value.items, isEmpty);

      await history.refresh(silent: false);
      expect(history.inbox.value.items.single.id, 'rental');
      expect(alerts, isEmpty);
    });
    testWidgets(
      'loading keeps all section headings at their empty inbox positions',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final response = Completer<NotificationInboxPage>();
        final repository = FakeNotificationRepository()
          ..onGet = (_, _) => response.future;
        final service = AppNotificationService.history(repository: repository);
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
          notification(
            id: 'app',
            category: AppNotificationCategory.app,
            title: 'ยืนยันตัวตนสำเร็จ',
          ),
        ]);
      final service = AppNotificationService.history(repository: repository);
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

    testWidgets('mark all persists read state on the history page', (
      tester,
    ) async {
      final repository = FakeNotificationRepository()
        ..page = inboxPage([
          notification(id: 'app', category: AppNotificationCategory.app),
        ]);
      final service = AppNotificationService.history(repository: repository);
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
      final service = AppNotificationService.history(
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
}
