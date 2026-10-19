import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';
import 'package:frontend/features/rental_item/domain/entities/rental_item.dart';

void main() {
  final newPhoto = RentalItemImage(
    bytes: Uint8List.fromList([1]),
    fileName: 'new.jpg',
  );
  ItemEditDraft draft(List<RentalItemPhoto>? order) => ItemEditDraft(
    itemId: 1,
    name: 'Camera',
    category: 'กล้อง',
    description: 'รายละเอียด',
    rentalType: 'รายวัน',
    price: 300,
    retainedImageUrls: const ['old-a.jpg', 'old-b.jpg'],
    newImages: [newPhoto],
    imageOrder: order,
  );

  test('new cover remains before retained images after upload', () {
    expect(
      draft([
        RentalItemPhoto.local(newPhoto),
        const RentalItemPhoto.remote('old-b.jpg'),
        const RentalItemPhoto.remote('old-a.jpg'),
      ]).resolveImageUrls(['uploaded.jpg']),
      ['uploaded.jpg', 'old-b.jpg', 'old-a.jpg'],
    );
  });

  test('legacy callers retain their original ordering', () {
    expect(draft(null).resolveImageUrls(['uploaded.jpg']), [
      'old-a.jpg',
      'old-b.jpg',
      'uploaded.jpg',
    ]);
  });

  test(
    'incomplete, duplicated or foreign photo references cannot be saved',
    () {
      for (final order in [
        <RentalItemPhoto>[],
        const [
          RentalItemPhoto.remote('old-a.jpg'),
          RentalItemPhoto.remote('old-a.jpg'),
        ],
        const [RentalItemPhoto.remote('foreign.jpg')],
      ]) {
        expect(
          () => draft(order).resolveImageUrls(['uploaded.jpg']),
          throwsFormatException,
        );
      }
      expect(() => draft(null).resolveImageUrls([]), throwsFormatException);
    },
  );
}
