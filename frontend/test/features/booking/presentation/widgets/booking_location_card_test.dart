import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/booking/presentation/widgets/booking_location_card.dart';

void main() {
  group('BookingLocationCard Tests', () {
    testWidgets('displays the meeting point and its details', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BookingLocationCard(
              location: 'Library',
              locationAddress: 'Bangkok',
            ),
          ),
        ),
      );

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Bangkok'), findsOneWidget);
    });

    test('the booking message preserves its pickup snapshot', () {
      final now = DateTime(2026, 9, 10);
      final req = BookingRequestData(
        item: BookingItemInfo.defaultMockItem,
        startDate: now,
        endDate: now.add(const Duration(days: 2)),
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 18, minute: 0),
        location: 'ไอคอนสยาม (ICONSIAM)',
        locationAddress: '299 ถนนเจริญนคร กรุงเทพฯ',
        latitude: 13.7267,
        longitude: 100.5108,
      );

      final payload = req.toChatMessagePayload();
      expect(payload, contains('ไอคอนสยาม (ICONSIAM)'));
      expect(payload, contains('"latitude":13.7267'));
      expect(payload, contains('"longitude":100.5108'));
      expect(payload, isNot(contains('locationNote')));

      final parsed = BookingRequestData.fromChatMessage(payload);
      expect(parsed, isNotNull);
      expect(parsed!.location, 'ไอคอนสยาม (ICONSIAM)');
      expect(parsed.locationAddress, '299 ถนนเจริญนคร กรุงเทพฯ');
      expect(parsed.latitude, 13.7267);
      expect(parsed.longitude, 100.5108);
    });
  });
}
