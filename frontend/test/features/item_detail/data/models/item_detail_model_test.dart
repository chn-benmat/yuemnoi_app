import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/data/models/item_detail_model.dart';

void main() {
  test(
    'maps item, owner profile, reviews, and ownership from Supabase rows',
    () {
      final item = ItemDetailModel.fromRecords(
        item: {
          'id': 7,
          'user_id': 'owner-id',
          'item_name': 'ชุดรวมเลนส์รวม',
          'item_image_url': ['https://example.com/lens.jpg'],
          'description': 'อุปกรณ์ถ่ายภาพ',
          'category': 'กล้องและอุปกรณ์ถ่ายภาพ',
          'price': 1000,
          'status': 'verified',
          'type': 'รายวัน',
        },
        profilesByUserId: {
          'owner-id': {
            'user_id': 'owner-id',
            'email': 'jessica@example.com',
            'user_image_url': 'https://example.com/jessica.jpg',
          },
          'reviewer-id': {
            'user_id': 'reviewer-id',
            'email': 'mark@example.com',
            'user_image_url': null,
          },
        },
        reviews: [
          {
            'id': 11,
            'user_id': 'reviewer-id',
            'rating': '4.5',
            'description': 'อุปกรณ์อยู่ในสภาพสมบูรณ์',
          },
        ],
        currentUserId: 'owner-id',
      );

      expect(item.id, 7);
      expect(item.owner.displayName, 'jessica');
      expect(item.owner.imageUrl, 'https://example.com/jessica.jpg');
      expect(item.isOwner, isTrue);
      expect(item.unitLabel, 'วัน');
      expect(item.reviews.single.reviewer.displayName, 'mark');
      expect(item.averageRating, 4.5);
    },
  );

  test('uses safe fallbacks for nullable profile and item values', () {
    final item = ItemDetailModel.fromRecords(
      item: {
        'id': 8,
        'user_id': 'owner-id',
        'item_name': null,
        'item_image_url': null,
        'description': '',
        'category': null,
        'price': null,
        'status': null,
        'type': 'รายชั่วโมง',
      },
      profilesByUserId: const {},
      reviews: const [],
      currentUserId: 'someone-else',
    );

    expect(item.name, 'อุปกรณ์ให้เช่า');
    expect(item.owner.displayName, 'ผู้ใช้งาน Yuemnoi');
    expect(item.imageUrls, isEmpty);
    expect(item.price, 0);
    expect(item.isOwner, isFalse);
    expect(item.unitLabel, 'ชั่วโมง');
    expect(item.averageRating, 0);
  });
}
