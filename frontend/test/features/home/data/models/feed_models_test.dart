import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/data/models/feed_category_model.dart';
import 'package:frontend/features/home/data/models/feed_item_model.dart';

void main() {
  test(
    'feed item keeps API aliases, coercions, and defaults on round trip',
    () {
      final item = FeedItemModel.fromJson({
        'id': 7,
        'item_name': 'Camera',
        'category': 'กล้อง',
        'item_image_url': 'image',
        'price': 120.9,
        'paid_booking_count': 3,
        'is_verified': 'true',
        'tags': ['tag', 1, null],
        'distance_km': 4.2,
        'pickup_latitude': 13.7,
        'pickup_longitude': 100.5,
      });
      expect(item.id, '7');
      expect(item.title, 'Camera');
      expect(item.categoryId, 'กล้อง');
      expect(item.rawCategory, 'กล้อง');
      expect(item.imageUrl, 'image');
      expect(item.price, 120);
      expect(item.paidBookingCount, 3);
      expect(item.isVerified, false);
      expect(item.tags, ['tag', '1', 'null']);
      expect(item.distanceKm, isNull);
      expect(item.pickupLatitude, 13.7);
      expect(item.pickupLongitude, 100.5);
      expect(
        item.toJson().keys,
        unorderedEquals([
          'id',
          'title',
          'description',
          'category_id',
          'raw_category',
          'price',
          'price_unit',
          'rating',
          'review_count',
          'paid_booking_count',
          'is_rental_occupied',
          'is_verified',
          'owner_name',
          'is_owner',
          'owner_avatar_url',
          'image_url',
          'is_curated',
          'is_favorite',
          'tags',
          'location_name',
          'pickup_latitude',
          'pickup_longitude',
        ]),
      );
      expect(FeedItemModel.fromJson(item.toJson()), item);
      expect(FeedItemModel.fromJson({}).categoryId, 'all');
      expect(FeedItemModel.fromJson({}).paidBookingCount, 0);
    },
  );

  test('feed category keeps snake case and nullable icon output', () {
    final category = FeedCategoryModel.fromJson({
      'id': 'all',
      'name': 'ทั้งหมด',
    });
    expect(category.toJson(), {
      'id': 'all',
      'name': 'ทั้งหมด',
      'icon_name': null,
    });
  });
}
