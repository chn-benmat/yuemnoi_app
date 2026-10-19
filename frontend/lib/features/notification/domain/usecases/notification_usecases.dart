import '../entities/app_notification.dart';
import '../repositories/notification_repository.dart';

class GetNotificationInbox {
  const GetNotificationInbox(this.repository);
  final NotificationRepository repository;
  Future<NotificationInboxPage> call({int limit = 50, int offset = 0}) =>
      repository.getInbox(limit: limit, offset: offset);
}

class MarkNotificationRead {
  const MarkNotificationRead(this.repository);
  final NotificationRepository repository;
  Future<void> call(AppNotification notification) =>
      repository.markRead(notification.id, readThrough: notification.updatedAt);
}

class MarkAllNotificationsRead {
  const MarkAllNotificationsRead(this.repository);
  final NotificationRepository repository;
  Future<void> call({DateTime? readThrough}) =>
      repository.markAllRead(readThrough: readThrough);
}
