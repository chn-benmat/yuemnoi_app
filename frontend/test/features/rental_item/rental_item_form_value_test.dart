import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/rental_item/presentation/widgets/rental_item_form_value.dart';

void main() {
  test('hourly listing sends the canonical hourly type', () {
    const value = RentalItemFormValue(hourlyPrice: '50', dailyPrice: '300');

    expect(value.rentalType, 'hourly');
    expect((value.hourlyRate, value.dailyRate), (50, 300));
  });

  test('daily-only listing sends the canonical daily type', () {
    const value = RentalItemFormValue(dailyPrice: '300');

    expect(value.rentalType, 'daily');
    expect((value.hourlyRate, value.dailyRate), (null, 300));
  });
}
