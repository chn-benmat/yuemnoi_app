import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/pickup_location.dart';

void main() {
  test('legacy listings have no implicit location', () {
    expect(PickupLocation.fromJson({'item_name': 'camera'}), isNull);
    expect(
      PickupLocation.fromJson({
        'pickup_location': 'place',
        'pickup_latitude': 91,
        'pickup_longitude': 100,
      }),
      isNull,
    );
  });
  test('coordinates on the equator and prime meridian remain valid', () {
    final location = PickupLocation.fromJson({
      'pickup_location': 'Meeting point',
      'pickup_latitude': '0',
      'pickup_longitude': 0,
      'pickup_address': 'Address',
      'pickup_note': 'Gate 1',
    });
    expect(location, isNotNull);
    expect(location!.toJson()['pickup_latitude'], 0);
    expect(PickupLocation.fromJson(location.toJson()), location);
  });
  test('rejects nonfinite and incomplete coordinates', () {
    expect(
      PickupLocation.fromJson({
        'pickup_location': 'place',
        'pickup_latitude': 'NaN',
        'pickup_longitude': 100,
      }),
      isNull,
    );
    expect(
      PickupLocation.fromJson({
        'pickup_location': 'place',
        'pickup_latitude': 13,
      }),
      isNull,
    );
  });
}
