import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/rental_item/data/models/rental_item_model.dart';

void main() {
  test('rental item filters image types and keeps numeric ids strict', () {
    final item = RentalItemModel.fromJson({
      'id': 4.9,
      'item_image_url': ['image', null, 1, ''],
    });
    expect(item.id, 4);
    expect(item.imageUrls, ['image', '']);
    expect(RentalItemModel.fromJson({'id': 1}).imageUrls, isEmpty);
    expect(() => RentalItemModel.fromJson({'id': '1'}), throwsFormatException);
  });
}
