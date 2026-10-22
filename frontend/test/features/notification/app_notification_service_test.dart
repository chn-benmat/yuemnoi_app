import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/active_conversation_tracker.dart';
import 'package:frontend/core/services/app_notification_service.dart';

import 'support/fake_notification_repository.dart';

void main() {
  test('notification badge excludes unread chats and read history', () {
    final state = NotificationInboxState(
      items: [
        notification(category: AppNotificationCategory.chat),
        notification(id: 'read', isRead: true),
      ],
      unreadCount: 1,
    );
    expect(state.hasUnreadNotification, isFalse);
    expect(const NotificationInboxState().hasUnreadNotification, isFalse);
    for (final category in [
      AppNotificationCategory.rental,
      AppNotificationCategory.app,
    ]) {
      expect(
        NotificationInboxState(
          items: [notification(category: category)],
        ).hasUnreadNotification,
        isTrue,
      );
    }
  });

  late FakeNotificationRepository repository;
  late AppNotificationService service;
  late List<AppNotification> events;

  setUp(() {
    repository = FakeNotificationRepository();
    service = AppNotificationService(
      repository: repository,
      pollInterval: const Duration(hours: 1),
    );
    events = [];
    service.foregroundEvents.listen(events.add);
  });

  tearDown(() {
    ActiveConversationTracker.instance.clearActive();
    service.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'initial history and resume backlog are silent; new events are delivered once',
    () async {
      repository.page = inboxPage([notification(id: 'old')]);
      service.setSession('alice');
      await service.refresh();
      await settle();
      expect(service.inbox.value.unreadCount, 1);
      expect(events, isEmpty);

      repository.page = inboxPage([
        notification(id: 'new', second: 2),
      ], second: 3);
      await service.refresh(silent: false);
      await service.handlePush({'notification_id': 'new'});
      await settle();
      expect(events.map((item) => item.id), ['new']);

      service.setForeground(false);
      repository.page = inboxPage([
        notification(id: 'background', second: 4),
      ], second: 5);
      await service.handlePush({'notification_id': 'background'});
      service.setForeground(true);
      await service.refresh();
      await settle();
      expect(events.map((item) => item.id), ['new']);

      repository.page = inboxPage([
        notification(id: 'resumed', second: 6),
      ], second: 7);
      await service.refresh(silent: false);
      await settle();
      expect(events.map((item) => item.id), ['new', 'resumed']);
    },
  );

  test(
    'reconnect refreshes unread history without replaying missed events',
    () async {
      service.setSession('alice');
      await service.refresh();
      repository.getError = const NotificationFailure('offline');
      await service.refresh(silent: false);
      expect(service.inbox.value.error, 'offline');

      repository.getError = null;
      repository.page = inboxPage([
        notification(id: 'offline-event', second: 2),
      ], second: 3);
      await service.refresh(silent: false);
      await settle();
      expect(service.inbox.value.unreadCount, 1);
      expect(events, isEmpty);

      repository.page = inboxPage([
        notification(id: 'live', second: 4),
      ], second: 5);
      await service.refresh(silent: false);
      await settle();
      expect(events.single.id, 'live');
    },
  );

  test(
    'one conversation row can alert again for a later message version',
    () async {
      repository.page = inboxPage([
        notification(
          id: 'room',
          category: AppNotificationCategory.chat,
          conversationId: 'conv',
        ),
      ]);
      service.setSession('alice');
      await service.refresh();
      repository.page = inboxPage([
        notification(
          id: 'room',
          category: AppNotificationCategory.chat,
          conversationId: 'conv',
          second: 2,
          unreadCount: 2,
        ),
      ], second: 3);
      await service.refresh(silent: false);
      repository.page = inboxPage([
        notification(
          id: 'room',
          category: AppNotificationCategory.chat,
          conversationId: 'conv',
          second: 4,
          unreadCount: 3,
        ),
      ], second: 5);
      await service.refresh(silent: false);
      await settle();
      expect(service.inbox.value.items, hasLength(1));
      expect(service.inbox.value.items.single.unreadCount, 3);
      expect(events, hasLength(2));
    },
  );

  test('active room and actor pre-read changes never alert', () async {
    service.setSession('alice');
    await service.refresh();
    ActiveConversationTracker.instance.setActive('active');
    repository.page = inboxPage([
      notification(
        id: 'chat',
        category: AppNotificationCategory.chat,
        conversationId: 'active',
        second: 2,
      ),
      notification(
        id: 'actor',
        category: AppNotificationCategory.rental,
        second: 2,
        isRead: true,
      ),
    ], second: 3);
    await service.refresh(silent: false);
    await settle();
    expect(events, isEmpty);
    expect(repository.conversationReads, ['active']);
  });

  test('late response from previous account cannot repopulate inbox', () async {
    final aliceRequest = Completer<NotificationInboxPage>();
    final bobRequest = Completer<NotificationInboxPage>();
    var calls = 0;
    repository.onGet = (_, _) =>
        calls++ == 0 ? aliceRequest.future : bobRequest.future;
    service.setSession('alice');
    service.setSession('bob');
    bobRequest.complete(inboxPage([notification(id: 'bob-only')]));
    await service.refresh();
    aliceRequest.complete(inboxPage([notification(id: 'alice-secret')]));
    await settle();
    expect(service.inbox.value.items.map((item) => item.id), ['bob-only']);
    service.setSession(null);
    expect(service.inbox.value.items, isEmpty);
    expect(service.inbox.value.isAuthenticated, false);
  });

  test(
    'read sync uses server state and does not mask a failed mutation',
    () async {
      repository.page = inboxPage([notification(id: 'unread')]);
      service.setSession('alice');
      await service.refresh();
      repository.readError = const NotificationFailure('save failed');
      await expectLater(
        service.markRead('unread'),
        throwsA(isA<NotificationFailure>()),
      );
      expect(service.inbox.value.items.single.isRead, false);
      expect(service.inbox.value.error, 'save failed');

      repository.readError = null;
      await service.markRead('unread');
      expect(repository.lastReadThrough, notificationTestTime);
      expect(service.inbox.value.unreadCount, 0);
      expect(service.inbox.value.items.single.isRead, true);

      repository.page = inboxPage([
        notification(id: 'another-device', isRead: true),
      ], second: 4);
      await service.refresh(silent: false);
      expect(service.inbox.value.items.first.isRead, true);
      await settle();
      expect(events, isEmpty);
    },
  );

  test(
    'old push delivery after initial history does not replay an alert',
    () async {
      repository.page = inboxPage([notification(id: 'old')], second: 5);
      service.setSession('alice');
      await service.refresh();
      await service.handlePush({'notification_id': 'old'});
      await settle();
      expect(events, isEmpty);
    },
  );

  test(
    'poll refreshes older loaded pages to synchronize read changes from another device',
    () async {
      service.dispose();
      service = AppNotificationService(
        repository: repository,
        pageSize: 2,
        pollInterval: const Duration(hours: 1),
      );
      var rows = [
        notification(id: 'one'),
        notification(id: 'two'),
        notification(id: 'older'),
      ];
      repository.onGet = (limit, offset) async =>
          inboxPage(rows.skip(offset).take(limit).toList());
      service.setSession('alice');
      await service.refresh();
      await service.loadMore();
      expect(service.inbox.value.items, hasLength(3));
      repository.offsets.clear();
      rows = [rows[0], rows[1], rows[2].asRead(notificationTestTime)];
      await service.refresh(silent: false);
      expect(repository.offsets, [0, 2]);
      expect(
        service.inbox.value.items
            .singleWhere((item) => item.id == 'older')
            .isRead,
        true,
      );
    },
  );

  test(
    'read mutation waits for an older in-flight snapshot before fetching its saved result',
    () async {
      repository.page = inboxPage([notification(id: 'read-me')]);
      service.setSession('alice');
      await service.refresh();
      final stalePage = repository.page;
      final staleRequest = Completer<NotificationInboxPage>();
      var requests = 0;
      repository.onGet = (_, _) =>
          requests++ == 0 ? staleRequest.future : Future.value(repository.page);
      final pendingPoll = service.refresh(silent: false);
      final read = service.markRead('read-me');
      await settle();
      staleRequest.complete(stalePage);
      await pendingPoll;
      await read;
      expect(service.inbox.value.items.single.isRead, true);
      expect(service.inbox.value.unreadCount, 0);
      expect(requests, 2);
    },
  );
}
