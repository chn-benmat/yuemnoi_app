import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/rental_countdown_timer_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('th', null);
  });

  group('RentalCountdownTimerWidget Tests', () {
    testWidgets('renders active countdown when endDateTime is in the future', (tester) async {
      final futureDate = DateTime.now().add(const Duration(hours: 3, minutes: 25, seconds: 10));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RentalCountdownTimerWidget(
              endDateTime: futureDate,
            ),
          ),
        ),
      );
      await tester.pump();

      // Check header text
      expect(find.textContaining('ช่วงเวลาเช่า (Active)'), findsOneWidget);
      expect(find.text('นับถอยหลัง'), findsOneWidget);
      expect(find.text('ชม.'), findsOneWidget);
      expect(find.text('นาที'), findsOneWidget);
      expect(find.text('วินาที'), findsOneWidget);
    });

    testWidgets('renders overdue state when endDateTime is in the past', (tester) async {
      final pastDate = DateTime.now().subtract(const Duration(hours: 1, minutes: 12));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RentalCountdownTimerWidget(
              endDateTime: pastDate,
            ),
          ),
        ),
      );
      await tester.pump();

      // Check overdue header text
      expect(find.textContaining('เลยกำหนดส่งคืน (Overdue)'), findsOneWidget);
      expect(find.text('เลทสะสม'), findsOneWidget);
      expect(find.textContaining('ส่งคืนล่าช้า'), findsOneWidget);
    });

    testWidgets('allows switching between normal and simulated overdue mode', (tester) async {
      final futureDate = DateTime.now().add(const Duration(hours: 5));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RentalCountdownTimerWidget(
              endDateTime: futureDate,
              showDemoSwitcher: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Initially active
      expect(find.textContaining('ช่วงเวลาเช่า (Active)'), findsOneWidget);

      // Tap "ส่งคืนเลท" demo chip
      await tester.tap(find.text('ส่งคืนเลท'));
      await tester.pump();

      // Should now show overdue view
      expect(find.textContaining('เลยกำหนดส่งคืน (Overdue)'), findsOneWidget);

      // Tap "กำลังเช่า" demo chip back
      await tester.tap(find.text('กำลังเช่า'));
      await tester.pump();

      expect(find.textContaining('ช่วงเวลาเช่า (Active)'), findsOneWidget);
    });
  });
}
