import '../entities/app_notification.dart';

abstract interface class NotificationRepository {
  Future<NotificationInboxPage> getInbox({int limit = 50, int offset = 0});
  Future<void> markRead(String id, {DateTime? readThrough});
  Future<void> markAllRead({DateTime? readThrough});
  Future<void> markConversationRead(String conversationId);
  void close();
}
