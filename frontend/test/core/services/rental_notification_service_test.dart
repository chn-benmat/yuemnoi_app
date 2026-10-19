import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/chat_notification_service.dart';
import 'package:frontend/core/services/rental_notification_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

class _MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class _MockChatNotificationService extends Mock
    implements ChatNotificationService {}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('th', null);
    registerFallbackValue(const NotificationDetails());
  });

  group('RentalNotificationService Formatting Tests', () {
    test('formatDuration formats days and hours correctly', () {
      const diff = Duration(days: 2, hours: 3, minutes: 15);
      final text = RentalNotificationService.formatDuration(
        diff,
        isOverdue: false,
      );
      expect(text, '2 วัน 3 ชม. 15 นาที');
    });

    test('formatDuration formats hours and minutes correctly', () {
      const diff = Duration(hours: 4, minutes: 20);
      final text = RentalNotificationService.formatDuration(
        diff,
        isOverdue: false,
      );
      expect(text, '4 ชม. 20 นาที');
    });

    test('formatDuration formats minutes only correctly', () {
      const diff = Duration(minutes: 35);
      final text = RentalNotificationService.formatDuration(
        diff,
        isOverdue: false,
      );
      expect(text, '35 นาที');
    });

    test('formatDuration handles overdue hours and minutes', () {
      const diff = Duration(hours: 90, minutes: 12);
      final text = RentalNotificationService.formatDuration(
        diff,
        isOverdue: true,
      );
      expect(text, '90 ชม. 12 นาที');
    });

    test('formatDueDate formats thai date correctly', () {
      final dt = DateTime(2026, 9, 21, 17, 0);
      final formatted = RentalNotificationService.formatDueDate(dt);
      expect(formatted, contains('21'));
      expect(formatted, contains('17:00'));
    });
  });

  group('RentalNotificationService Content Generation Tests', () {
    test(
      'buildNotificationContent generates active rental reminder when not overdue',
      () {
        final now = DateTime(2026, 9, 20, 10, 0);
        final end = DateTime(2026, 9, 20, 12, 30);

        final content = RentalNotificationService.buildNotificationContent(
          itemTitle: 'กล้อง Sony A7 IV',
          endDateTime: end,
          now: now,
        );

        expect(content.isOverdue, isFalse);
        expect(
          content.title,
          contains('🔔 แจ้งเตือนเวลาเช่า: กล้อง Sony A7 IV'),
        );
        expect(content.body, contains('เหลือเวลาอีก 2 ชม. 30 นาที'));
        expect(content.body, contains('กรุณาเตรียมส่งคืนอุปกรณ์ตามเวลา'));
      },
    );

    test(
      'buildNotificationContent generates overdue notification when past due',
      () {
        final now = DateTime(2026, 9, 21, 14, 0);
        final end = DateTime(2026, 9, 21, 10, 0);

        final content = RentalNotificationService.buildNotificationContent(
          itemTitle: 'กีตาร์โปร่ง Yamaha F310',
          endDateTime: end,
          now: now,
        );

        expect(content.isOverdue, isTrue);
        expect(
          content.title,
          contains('🚨 แจ้งเตือนเลยกำหนดส่งคืน: กีตาร์โปร่ง Yamaha F310'),
        );
        expect(content.body, contains('เลยกำหนดส่งคืนมาแล้ว 4 ชม. 0 นาที'));
        expect(content.body, contains('กรุณาดำเนินการส่งคืนอุปกรณ์'));
      },
    );
  });

  group('RentalNotificationService Plugin Interaction Tests', () {
    late _MockFlutterLocalNotificationsPlugin mockPlugin;
    late _MockChatNotificationService mockChatService;
    late RentalNotificationService service;

    setUp(() {
      mockPlugin = _MockFlutterLocalNotificationsPlugin();
      mockChatService = _MockChatNotificationService();
      service = RentalNotificationService(
        notificationsPlugin: mockPlugin,
        chatNotificationService: mockChatService,
      );

      when(() => mockChatService.playMessageSound()).thenAnswer((_) async {});

      when(
        () => mockPlugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockPlugin.cancel(id: any(named: 'id')),
      ).thenAnswer((_) async {});
    });

    test(
      'notifyRentalTimeStatus calls mockPlugin.show with correct payload and title',
      () async {
        final end = DateTime.now().add(const Duration(hours: 3));

        await service.notifyRentalTimeStatus(
          itemTitle: 'iPhone 15 Pro 128GB',
          endDateTime: end,
          bookingId: 42,
          conversationId: 'conv-42',
        );

        verify(() => mockChatService.playMessageSound()).called(1);
        verify(
          () => mockPlugin.show(
            id: any(named: 'id'),
            title: any(named: 'title', that: contains('iPhone 15 Pro 128GB')),
            body: any(named: 'body', that: contains('เหลือเวลาอีก')),
            notificationDetails: any(named: 'notificationDetails'),
            payload: 'conv-42',
          ),
        ).called(1);
      },
    );

    test(
      'cancelRentalReminders cancels notification IDs for the booking',
      () async {
        await service.cancelRentalReminders(42);

        // Verify that primary and offset IDs are cancelled
        verify(() => mockPlugin.cancel(id: 4201)).called(1);
        verify(() => mockPlugin.cancel(id: 4210)).called(1);
      },
    );

    test(
      'scheduleRentalReminders does not show instant notification when rental has already ended',
      () async {
        final pastDate = DateTime.now().subtract(const Duration(hours: 1));

        await service.scheduleRentalReminders(
          itemTitle: 'MacBook Pro',
          endDateTime: pastDate,
          bookingId: 88,
        );

        // Verify that no instant notification or sound was played on chat open
        verifyNever(
          () => mockPlugin.show(
            id: any(named: 'id'),
            title: any(named: 'title'),
            body: any(named: 'body'),
            notificationDetails: any(named: 'notificationDetails'),
            payload: any(named: 'payload'),
          ),
        );
        verifyNever(() => mockChatService.playMessageSound());
      },
    );
  });
}
