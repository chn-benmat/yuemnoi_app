import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';
import 'package:frontend/core/widgets/pickup_location_field.dart';
import 'package:frontend/features/booking/presentation/pages/location_picker_map_page.dart';

void main() {
  for (final throwsException in [false, true]) {
    testWidgets(
      'shows feedback when Google Maps ${throwsException ? 'throws' : 'cannot open'}',
      (tester) async {
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (throwsException) {
              throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
            }
            return false;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PickupLocationCard(
                location: PickupLocation(
                  name: 'Library',
                  address: 'Bangkok',
                  latitude: 13.7,
                  longitude: 100.5,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('จุดนัดรับสินค้า'));
        await tester.pumpAndSettle();

        expect(
          find.text('ไม่สามารถเปิด Google Maps ได้ในขณะนี้'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

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
