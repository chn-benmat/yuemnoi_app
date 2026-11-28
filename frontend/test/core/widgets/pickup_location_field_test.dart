import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';
import 'package:frontend/core/widgets/pickup_location_field.dart';
import 'package:frontend/features/booking/presentation/pages/pickup_details_page.dart';

void main() {
  testWidgets('does not offer a manual editor when Longdo is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PickupDetailsPage()));

    expect(find.byType(TextFormField), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('แผนที่ Longdo ยังไม่พร้อมใช้งาน'), findsOneWidget);
  });

  testWidgets('closing the unavailable picker preserves the saved location', (
    tester,
  ) async {
    const saved = PickupLocation(
      name: 'Library',
      address: 'Bangkok',
      latitude: 13.75,
      longitude: 100.5,
    );
    final selections = <PickupLocation>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickupLocationField(value: saved, onChanged: selections.add),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pickup-location-field')));
    await tester.pumpAndSettle();

    expect(find.byType(PickupDetailsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text(saved.name), findsOneWidget);
    expect(selections, isEmpty);
  });
}
