import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/location_service.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/booking/presentation/widgets/booking_location_card.dart';

void main() {
  group('BookingLocationCard Tests', () {
    testWidgets('renders location title, note, and coordinates badge in editable mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BookingLocationCard(
                location: 'ซีคอน บางแค',
                locationNote: 'เลือกโดยผู้ปล่อยเช่า',
                latitude: 13.7126,
                longitude: 100.4332,
                isEditable: true,
              ),
            ),
          ),
        ),
      );

      // Verify location title and note
      expect(find.text('สถานที่นัดพบ'), findsOneWidget);
      expect(find.text('ซีคอน บางแค'), findsOneWidget);
      expect(find.text('เลือกโดยผู้ปล่อยเช่า'), findsOneWidget);

      // Verify coordinates badge is rendered
      expect(find.textContaining('13.7126, 100.4332'), findsOneWidget);

      // Verify map action label is shown
      expect(find.text('เลือกบนแผนที่'), findsOneWidget);
      expect(find.text('แตะเพื่อเปลี่ยนจุดปักหมุด'), findsOneWidget);
    });

    testWidgets('renders non-editable mode with Google Maps action label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BookingLocationCard(
                location: 'สยามพารากอน (Siam Paragon)',
                locationNote: 'ระบุโดยคุณ',
                latitude: 13.7460,
                longitude: 100.5349,
                isEditable: false,
              ),
            ),
          ),
        ),
      );

      // Verify location title
      expect(find.text('สยามพารากอน (Siam Paragon)'), findsOneWidget);
      expect(find.text('ระบุโดยคุณ'), findsOneWidget);
      expect(find.textContaining('13.7460, 100.5349'), findsOneWidget);

      // In non-editable mode, "เลือกบนแผนที่" header action is not present
      expect(find.text('เลือกบนแผนที่'), findsNothing);
      expect(find.text('เปิดดูใน Google Maps'), findsOneWidget);
    });

    test('LocationService popular landmarks are well populated', () {
      expect(LocationService.popularLandmarks, isNotEmpty);
      final seacon = LocationService.popularLandmarks.firstWhere(
        (l) => l.name == 'ซีคอน บางแค',
      );
      expect(seacon.latitude, 13.7126);
      expect(seacon.longitude, 100.4332);
    });

    test('BookingRequestData serializes and deserializes coordinates', () {
      final now = DateTime(2026, 9, 10);
      final req = BookingRequestData(
        item: BookingItemInfo.defaultMockItem,
        startDate: now,
        endDate: now.add(const Duration(days: 2)),
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 18, minute: 0),
        location: 'ไอคอนสยาม (ICONSIAM)',
        locationNote: 'หน้าร้านกาแฟ ชั้น G',
        latitude: 13.7267,
        longitude: 100.5108,
      );

      final payload = req.toChatMessagePayload();
      expect(payload, contains('ไอคอนสยาม (ICONSIAM)'));
      expect(payload, contains('"latitude":13.7267'));
      expect(payload, contains('"longitude":100.5108'));

      final parsed = BookingRequestData.fromChatMessage(payload);
      expect(parsed, isNotNull);
      expect(parsed!.location, 'ไอคอนสยาม (ICONSIAM)');
      expect(parsed.locationNote, 'หน้าร้านกาแฟ ชั้น G');
      expect(parsed.latitude, 13.7267);
      expect(parsed.longitude, 100.5108);
    });
  });
}
