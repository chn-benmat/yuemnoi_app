import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/app_notification_service.dart';
import 'package:frontend/features/notification/presentation/widgets/global_app_notification_listener.dart';

import 'support/fake_notification_repository.dart';

void main() {
  testWidgets('banner works above the router Overlay in MaterialApp.builder', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repository = FakeNotificationRepository();
    final service = AppNotificationService(
      repository: repository,
      pollInterval: const Duration(hours: 1),
    );
    addTearDown(service.dispose);
    var sounds = 0;
    service.setSession('alice');
    await service.refresh();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GlobalAppNotificationListener(
          service: service,
          playSound: () async {
            sounds++;
          },
          child: child!,
        ),
        home: const Scaffold(body: Text('แอป')),
      ),
    );
    repository.page = inboxPage([
      notification(id: 'above-router', second: 2),
    ], second: 3);
    await service.refresh(silent: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('หัวข้อ above-router'), findsOneWidget);
    expect(sounds, 1);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('หัวข้อ above-router'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets(
    'chat, rental and app events use foreground banners with sound; background is silent',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final repository = FakeNotificationRepository();
      final service = AppNotificationService(
        repository: repository,
        pollInterval: const Duration(hours: 1),
      );
      var sounds = 0;
      service.setSession('alice');
      await service.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: GlobalAppNotificationListener(
            service: service,
            playSound: () async {
              sounds++;
            },
            child: const Scaffold(body: Text('แอป')),
          ),
        ),
      );
      await tester.pump();

      var second = 2;
      for (final category in AppNotificationCategory.values) {
        repository.page = inboxPage([
          notification(id: category.name, category: category, second: second),
        ], second: second + 1);
        await service.refresh(silent: false);
        await tester.pumpAndSettle();
        expect(find.text('หัวข้อ ${category.name}'), findsOneWidget);
        second += 2;
      }
      expect(sounds, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      repository.page = inboxPage([
        notification(id: 'background', second: second),
      ], second: second + 1);
      await service.handlePush({'notification_id': 'background'});
      await tester.pump();
      expect(find.text('หัวข้อ background'), findsNothing);
      expect(sounds, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await service.refresh();
      await tester.pump();
      expect(find.text('หัวข้อ background'), findsNothing);
      expect(sounds, 3);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  testWidgets('sign-out removes an active private notification banner', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repository = FakeNotificationRepository();
    final service = AppNotificationService(
      repository: repository,
      pollInterval: const Duration(hours: 1),
    );
    service.setSession('alice');
    await service.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: GlobalAppNotificationListener(
          service: service,
          playSound: () async {},
          child: const Scaffold(),
        ),
      ),
    );
    repository.page = inboxPage([
      notification(id: 'private', second: 2),
    ], second: 3);
    await service.refresh(silent: false);
    await tester.pump();
    expect(find.text('หัวข้อ private'), findsOneWidget);
    service.setSession(null);
    await tester.pump();
    expect(find.text('หัวข้อ private'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
