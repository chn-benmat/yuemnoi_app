import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/models/rental_rates.dart';

void main() {
  test('a row with database rates shows its primary rate', () {
    expect(
      RentalRates.withPrimaryRate({
        'id': 1,
        'price': 75,
        'type': 'hourly',
        'hourly_rate': 80,
        'daily_rate': 300,
      }),
      {
        'id': 1,
        'price': 80,
        'type': 'hourly',
        'hourly_rate': 80,
        'daily_rate': 300,
      },
    );
    expect(
      RentalRates.withPrimaryRate({'hourly_rate': null, 'daily_rate': 410}),
      {'hourly_rate': null, 'daily_rate': 410, 'price': 410, 'type': 'daily'},
    );
  });

  test('a row without database rates keeps its legacy price', () {
    final row = {'price': 75, 'type': 'รายชั่วโมง'};
    expect(RentalRates.withPrimaryRate(row), same(row));
  });

  test('a row whose rates are both missing keeps its legacy price', () {
    final row = {
      'price': 75,
      'type': 'daily',
      'hourly_rate': null,
      'daily_rate': null,
    };
    expect(RentalRates.withPrimaryRate(row), same(row));
  });
}
