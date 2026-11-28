import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/fcm_service.dart';
import 'package:frontend/features/notification/domain/app_notification.dart';

void main() {
  test('skips chat and rental request pushes while the same room is open', () {
    for (final type in ['chat_message', 'rental_request_received']) {
      final notification = AppNotification(
        id: '1',
        type: type,
        title: '',
        body: '',
        conversationId: 'room',
      );
      expect(
        FcmService.canPresent(
          notification: notification,
          conversationVisible: true,
        ),
        isFalse,
      );
      expect(
        FcmService.canPresent(
          notification: notification,
          conversationVisible: false,
        ),
        isTrue,
      );
    }
  });

  test('still posts the queue turn alert when its room is open', () {
    const notification = AppNotification(
      id: '1',
      type: 'rental_queue_ready',
      title: '',
      body: '',
      conversationId: 'room',
    );
    expect(
      FcmService.canPresent(
        notification: notification,
        conversationVisible: true,
      ),
      isTrue,
    );
  });
}
