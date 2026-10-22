import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/app_notification_service.dart';

void main() {
  AppNotification notice(
    String id,
    int second, {
    String? itemId,
    String? bookingId,
    bool read = false,
    AppNotificationCategory category = AppNotificationCategory.rental,
  }) => AppNotification(
    id: id,
    category: category,
    type: id,
    title: id,
    body: 'สินค้า',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026).add(Duration(seconds: second)),
    itemId: itemId,
    bookingId: bookingId,
    readAt: read ? DateTime.utc(2026) : null,
    unreadCount: read ? 0 : 1,
  );

  test('shows latest status per item and uses its read state', () {
    final state = NotificationInboxState(
      items: [
        notice('started', 1, itemId: 'phone'),
        notice('returned', 3, itemId: 'phone', read: true),
        notice('requested', 2, itemId: 'phone'),
      ],
    );
    expect(state.visibleItems.map((item) => item.id), ['returned']);
    expect(state.hasUnreadNotification, isFalse);
    expect(state.items.length, 3);
    expect(
      NotificationInboxState(
        items: [
          ...state.items,
          notice('new-booking', 4, itemId: 'phone', bookingId: 'next'),
        ],
      ).visibleItems.single.id,
      'new-booking',
    );
  });

  test('keeps other items, system notices and missing references separate', () {
    final state = NotificationInboxState(
      items: [
        notice('phone', 1, itemId: 'phone'),
        notice('camera', 2, itemId: 'camera'),
        notice('booking-old', 3, bookingId: 'booking'),
        notice('booking-new', 4, bookingId: 'booking'),
        notice('unknown-a', 5),
        notice('unknown-b', 6),
        notice(
          'system-a',
          7,
          itemId: 'phone',
          category: AppNotificationCategory.app,
        ),
        notice(
          'system-b',
          8,
          itemId: 'phone',
          category: AppNotificationCategory.app,
        ),
      ],
    );
    expect(state.visibleItems.map((item) => item.id), [
      'system-b',
      'system-a',
      'unknown-b',
      'unknown-a',
      'booking-new',
      'camera',
      'phone',
    ]);
    expect(state.hasUnreadNotification, isTrue);
  });
}
