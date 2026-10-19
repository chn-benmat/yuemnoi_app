import '../../domain/entities/app_notification.dart';

abstract final class AppNotificationModel {
  static AppNotification fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final updatedAt = DateTime.tryParse('${json['updated_at']}');
    final createdAt = DateTime.tryParse('${json['created_at']}');
    if (id.isEmpty || updatedAt == null || createdAt == null) {
      throw const NotificationFailure('รูปแบบข้อมูลแจ้งเตือนไม่ถูกต้อง');
    }
    final readAt = DateTime.tryParse('${json['read_at']}');
    final isRead = json['is_read'] == true || readAt != null;
    final count = int.tryParse('${json['unread_count']}') ?? (isRead ? 0 : 1);
    return AppNotification(
      id: id,
      category: switch (json['category']) {
        'chat' => AppNotificationCategory.chat,
        'rental' => AppNotificationCategory.rental,
        _ => AppNotificationCategory.app,
      },
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Yuemnoi',
      body: json['body']?.toString() ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      readAt: readAt ?? (isRead ? updatedAt : null),
      unreadCount: isRead || count < 0 ? 0 : count,
      conversationId: _identifier(json['conversation_id']),
      bookingId: _identifier(json['booking_id']),
      itemId: _identifier(json['item_id']),
      data: Map<String, dynamic>.unmodifiable(
        json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : const {},
      ),
    );
  }

  static String? _identifier(Object? value) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }
}
