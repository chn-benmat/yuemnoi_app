enum AppNotificationCategory { chat, rental, app }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.readAt,
    this.unreadCount = 1,
    this.conversationId,
    this.bookingId,
    this.itemId,
    this.data = const {},
  });

  final String id;
  final AppNotificationCategory category;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? readAt;
  final int unreadCount;
  final String? conversationId;
  final String? bookingId;
  final String? itemId;
  final Map<String, dynamic> data;

  bool get isRead => readAt != null || unreadCount == 0;
  String get versionKey => '$id:${updatedAt.toUtc().toIso8601String()}';

  AppNotification asRead(DateTime at) => AppNotification(
    id: id,
    category: category,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    updatedAt: updatedAt,
    readAt: at,
    unreadCount: 0,
    conversationId: conversationId,
    bookingId: bookingId,
    itemId: itemId,
    data: data,
  );
}

class NotificationInboxPage {
  const NotificationInboxPage({
    required this.items,
    required this.unreadCount,
    required this.serverTime,
  });

  final List<AppNotification> items;
  final int unreadCount;
  final DateTime serverTime;
}

class NotificationFailure implements Exception {
  const NotificationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
