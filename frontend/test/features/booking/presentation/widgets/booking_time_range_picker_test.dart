import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';
import 'package:frontend/features/booking/presentation/widgets/booking_time_range_picker.dart';

void main() {
  group('BookingTimeRangePicker Tests', () {
    testWidgets(
      'renders วันนัดรับของ, เริ่มเช่า, and สิ้นสุดการเช่า in hourly mode',
      (tester) async {
        DateTime startDate = DateTime(2026, 9, 10);
        DateTime endDate = DateTime(2026, 9, 10);
        TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
        TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return BookingTimeRangePicker(
                    rentalType: BookingRentalType.hourly,
                    startDate: startDate,
                    endDate: endDate,
                    startTime: startTime,
                    endTime: endTime,
                    onDatesChanged: (s, e) {
                      setState(() {
                        startDate = s;
                        endDate = e;
                      });
                    },
                    onTimesChanged: (s, e) {
                      setState(() {
                        startTime = s;
                        endTime = e;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        );

        // Verify that 'วันนัดรับของ' label is rendered
        expect(find.text('วันนัดรับของ'), findsOneWidget);
        expect(find.text('10/09/2026'), findsOneWidget);

        // Verify that 'เวลาเริ่มเช่า' and 'เวลาคืนของ' labels are rendered
        expect(find.text('เวลาเริ่มเช่า'), findsOneWidget);
        expect(find.text('เวลาคืนของ'), findsOneWidget);

        // Verify times
        expect(find.text('09:00 น.'), findsOneWidget);
        expect(find.text('17:00 น.'), findsOneWidget);

        // Tap 'วันนัดรับของ' to open date picker
        await tester.tap(find.text('10/09/2026'));
        await tester.pumpAndSettle();

        expect(find.text('เลือกวันนัดรับของ'), findsOneWidget);
      },
    );

    testWidgets(
      'renders เริ่มเช่า and สิ้นสุดการเช่า in daily mode without redundant top date header',
      (tester) async {
        DateTime startDate = DateTime(2026, 9, 10);
        DateTime endDate = DateTime(2026, 9, 12);
        TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
        TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BookingTimeRangePicker(
                rentalType: BookingRentalType.daily,
                startDate: startDate,
                endDate: endDate,
                startTime: startTime,
                endTime: endTime,
              ),
            ),
          ),
        );

        // 'วันนัดรับของ' should not be shown in daily mode
        expect(find.text('วันนัดรับของ'), findsNothing);

        // 'วันที่เริ่มเช่า' and 'วันที่คืนของ' should be shown
        expect(find.text('วันที่เริ่มเช่า'), findsOneWidget);
        expect(find.text('วันที่คืนของ'), findsOneWidget);

        // Start and end dates in pills
        expect(find.text('10/09/2026'), findsOneWidget);
        expect(find.text('12/09/2026'), findsOneWidget);
      },
    );
  });
}
