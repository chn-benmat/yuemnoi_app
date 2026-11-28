import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';

void main() {
  test(
    'reads a meeting point without coordinates and serializes text only',
    () {
      final location = PickupLocation.fromJson({
        'pickup_location': ' Library ',
        'pickup_address': ' Bangkok ',
        'pickup_note': ' Gate 1 ',
      });
      expect(location, isNotNull);
      expect(location!.toJson(), {
        'pickup_location': 'Library',
        'pickup_address': 'Bangkok',
      });
    },
  );

  test('reads older meeting points regardless of the coordinate data', () {
    expect(
      PickupLocation.fromJson({
        'pickup_location': 'Library',
        'pickup_latitude': 'NaN',
        'pickup_longitude': 100,
      })?.name,
      'Library',
    );
    expect(PickupLocation.fromJson({'pickup_location': '  '}), isNull);
    expect(PickupLocation.fromJson({}), isNull);
  });

  test('retains a valid GPS pair used for nearby recommendations', () {
    final location = PickupLocation.fromJson({
      'pickup_location': 'Library',
      'pickup_latitude': '0',
      'pickup_longitude': 100.5,
    })!;
    expect(location.hasCoordinates, isTrue);
    expect(location.toJson()['pickup_latitude'], 0);
    expect(location.toJson()['pickup_longitude'], 100.5);
  });
}
