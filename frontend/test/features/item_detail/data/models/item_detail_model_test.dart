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
          'owner_hidden': true,
          'type': 'รายวัน',
        },
        profilesByUserId: {
          'owner-id': {
            'user_id': 'owner-id',
            'email': 'jessica@example.com',
            'user_image_url': 'https://example.com/jessica.jpg',
            'is_verified': true,
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
      expect(item.owner.isVerified, isTrue);
      expect(item.reviews.single.reviewer.isVerified, isFalse);
      expect(item.isOwner, isTrue);
      expect(item.ownerHidden, isTrue);
      expect(item.unitLabel, 'วัน');
      expect(item.hourlyPrice, isNull);
      expect(item.dailyPrice, 1000);
      expect(item.reviews.single.reviewer.displayName, 'mark');
      expect(item.averageRating, 4.5);
    },
  );

  test('reads the advertised prices from both item detail sources', () {
    final row = {
      'id': 7,
      'user_id': 'owner-id',
      'price': 75,
      'daily_price': 410,
      'type': 'hourly',
    };
    final items = [
      ItemDetailModel.fromRecords(
        item: row,
        profilesByUserId: const {},
        reviews: const [],
        currentUserId: null,
      ),
      ItemDetailModel.fromApiResponse(item: row, currentUserId: null),
    ];
    for (final item in items) {
      expect(item.hourlyPrice, 75);
      expect(item.dailyPrice, 410);
      expect(item.withVisibility(hidden: true).dailyPrice, 410);
    }
  });

  test('uses the per-unit rates computed by the database', () {
    // ฐานเป็นผู้ตีความ price/type/daily_price แอปจึงใช้เรตที่ฐานส่งมาตรง ๆ
    final row = {
      'id': 7,
      'user_id': 'owner-id',
      'price': 75,
      'daily_price': null,
      'type': 'hourly',
      'hourly_rate': 80,
      'daily_rate': 420,
    };
    final items = [
      ItemDetailModel.fromRecords(
        item: row,
        profilesByUserId: const {},
        reviews: const [],
        currentUserId: null,
      ),
      ItemDetailModel.fromApiResponse(item: row, currentUserId: null),
    ];
    for (final item in items) {
      expect(item.hourlyPrice, 80);
      expect(item.dailyPrice, 420);
      expect(item.withVisibility(hidden: true).dailyPrice, 420);
    }
  });

  test('keeps a missing database rate absent for that unit', () {
    final item = ItemDetailModel.fromApiResponse(
      item: {
        'id': 7,
        'user_id': 'owner-id',
        'price': 400,
        'type': 'daily',
        'hourly_rate': null,
        'daily_rate': 400,
      },
      currentUserId: null,
    );

    expect(item.hourlyPrice, isNull);
    expect(item.dailyPrice, 400);
  });

  test('models a queue hold separately from an open rental', () {
    final row = {
      'id': 7,
      'user_id': 'owner-id',
      'is_rental_occupied': false,
      'is_rental_queue_held': true,
    };
    final items = [
      ItemDetailModel.fromRecords(
        item: row,
        profilesByUserId: const {},
        reviews: const [],
        currentUserId: null,
      ),
      ItemDetailModel.fromApiResponse(item: row, currentUserId: null),
    ];

    for (final item in items) {
      expect(item.isRentalOccupied, isFalse);
      expect(item.isRentalQueueHeld, isTrue);
      expect(item.withVisibility(hidden: false).isRentalQueueHeld, isTrue);
    }
  });

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
    expect(item.owner.isVerified, isFalse);
    expect(item.imageUrls, isEmpty);
    expect(item.price, 0);
    expect(item.isOwner, isFalse);
    expect(item.unitLabel, 'ชั่วโมง');
    expect(item.averageRating, 0);
  });
}
