import 'package:frontend/features/notification/domain/entities/app_notification.dart';
import 'package:frontend/features/notification/domain/repositories/notification_repository.dart';

final notificationTestTime = DateTime.utc(2026, 10, 19, 9);

AppNotification notification({
  String id = 'notification-1',
  AppNotificationCategory category = AppNotificationCategory.chat,
  int second = 0,
  bool isRead = false,
  String? conversationId,
  int unreadCount = 1,
  String? title,
}) => AppNotification(
  id: id,
  category: category,
  type: switch (category) {
    AppNotificationCategory.chat => 'chat_message',
    AppNotificationCategory.rental => 'rental_confirmed',
    AppNotificationCategory.app => 'identity_approved',
  },
  title: title ?? 'หัวข้อ $id',
  body: 'รายละเอียด $id',
  createdAt: notificationTestTime,
  updatedAt: notificationTestTime.add(Duration(seconds: second)),
  readAt: isRead ? notificationTestTime : null,
  unreadCount: isRead ? 0 : unreadCount,
  conversationId: conversationId,
);

NotificationInboxPage inboxPage(
  List<AppNotification> items, {
  int second = 1,
}) => NotificationInboxPage(
  items: items,
  unreadCount: items
      .where((item) => !item.isRead)
      .fold(0, (total, item) => total + item.unreadCount),
  serverTime: notificationTestTime.add(Duration(seconds: second)),
);

class FakeNotificationRepository implements NotificationRepository {
  NotificationInboxPage page = inboxPage([]);
  Future<NotificationInboxPage> Function(int limit, int offset)? onGet;
  Object? getError;
  Object? readError;
  final reads = <String>[];
  final conversationReads = <String>[];
  final offsets = <int>[];
  DateTime? lastReadThrough;
  bool closed = false;

  @override
  Future<NotificationInboxPage> getInbox({
    int limit = 50,
    int offset = 0,
  }) async {
    offsets.add(offset);
    if (onGet != null) return onGet!(limit, offset);
    if (getError != null) throw getError!;
    return page;
  }

  @override
  Future<void> markRead(String id, {DateTime? readThrough}) async {
    if (readError != null) throw readError!;
    reads.add(id);
    lastReadThrough = readThrough;
    page = inboxPage(
      page.items
          .map((item) => item.id == id ? item.asRead(page.serverTime) : item)
          .toList(),
      second: page.serverTime.difference(notificationTestTime).inSeconds,
    );
  }

  @override
  Future<void> markAllRead({DateTime? readThrough}) async {
    if (readError != null) throw readError!;
    lastReadThrough = readThrough;
    page = inboxPage(
      page.items.map((item) => item.asRead(page.serverTime)).toList(),
      second: page.serverTime.difference(notificationTestTime).inSeconds,
    );
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    conversationReads.add(conversationId);
    page = inboxPage(
      page.items
          .map(
            (item) => item.conversationId == conversationId
                ? item.asRead(page.serverTime)
                : item,
          )
          .toList(),
      second: page.serverTime.difference(notificationTestTime).inSeconds,
    );
  }

  @override
  void close() => closed = true;
}
