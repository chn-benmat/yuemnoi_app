import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';
import 'package:frontend/core/widgets/pickup_location_field.dart';
import 'package:frontend/features/booking/presentation/pages/location_picker_map_page.dart';

void main() {
  testWidgets(
    'requires an explicit map confirmation and preserves a canceled selection',
    (tester) async {
      final form = GlobalKey<FormState>();
      final navigator = GlobalKey<NavigatorState>();
      PickupLocation? selected;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Form(
                key: form,
                child: PickupLocationField(
                  value: selected,
                  onChanged: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('กรุณาเลือกจุดนัดรับสินค้า'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pickup-location-field')));
      navigator.currentState!.pop(
        const LocationPickerResult(
          locationName: 'Library',
          locationNote: 'Gate 1',
          fullAddress: 'Bangkok',
          latitude: 13.7,
          longitude: 100.5,
        ),
      );
      await tester.pumpAndSettle();
    expect(find.text('กรุณาเลือกจุดนัดรับสินค้า'), findsNothing);
      expect(form.currentState!.validate(), isTrue);
      expect(selected!.name, 'Library');
      expect(selected!.note, 'Gate 1');
      await tester.tap(find.byKey(const Key('pickup-location-field')));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(selected!.name, 'Library');
      expect(selected!.latitude, 13.7);
    },
  );
}
