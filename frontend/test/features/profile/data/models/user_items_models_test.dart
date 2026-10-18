import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/models/favorite_item_model.dart';
import 'package:frontend/features/profile/data/models/user_item_model.dart';

void main() {
  group('UserItemModel', () {
    test('keeps category subtitles and flexible image representations', () {
      final model = UserItemModel.fromJson({
        'category': 'กล้อง',
        'item_image_url': ' , https://img.com/1.jpg, ,https://img.com/2.jpg ',
      });
      expect(model.title, 'อุปกรณ์');
      expect(model.subtitle, 'หมวดหมู่: กล้อง');
      expect(model.imageUrl, 'https://img.com/1.jpg');
      expect(model.imageCount, 2);
      expect(UserItemModel.fromJson({}).imageCount, 1);
      expect(UserItemModel.fromJson({}).subtitle, 'หมวดหมู่: ทั่วไป');
    });

    test('fromJson parses correctly with json list of images', () {
      final json = {
        'id': 10,
        'item_name': 'Sony Camera',
        'category': 'กล้อง',
        'description': 'Good condition',
        'price': 500.0,
        'item_image_url': ['https://img.com/1.jpg', 'https://img.com/2.jpg'],
      };

      final model = UserItemModel.fromJson(json);

      expect(model.id, 10);
      expect(model.title, 'Sony Camera');
      expect(model.subtitle, 'Good condition');
      expect(model.price, 500.0);
      expect(model.imageUrl, 'https://img.com/1.jpg');
      expect(model.imageCount, 2);

      final entity = model.toEntity();
      expect(entity.id, 10);
      expect(entity.title, 'Sony Camera');
    });

    test('fromJson parses string json image url', () {
      final json = {
        'id': 11,
        'item_name': 'Drone',
        'category': 'โดรน',
        'price': 800.0,
        'item_image_url': '["https://img.com/drone.jpg"]',
      };

      final model = UserItemModel.fromJson(json);

      expect(model.imageUrl, 'https://img.com/drone.jpg');
      expect(model.imageCount, 1);
    });
  });

  group('FavoriteItemModel', () {
    test('keeps caller owner names separate from item payloads', () {
      final model = FavoriteItemModel.fromJson({
        'owner_name': 'Ignored payload name',
        'item_image_url': [null, '', ' https://img.com/item.jpg '],
      });
      expect(model.id, 0);
      expect(model.ownerName, 'เจ้าของอุปกรณ์');
      expect(model.imageUrl, 'https://img.com/item.jpg');
      expect(FavoriteItemModel.fromJson({}, ownerName: '').ownerName, '');
    });

    test('fromJson parses correctly and converts toEntity', () {
      final json = {
        'id': 20,
        'item_name': 'MacBook Pro',
        'user_id': 'owner_1',
        'price': 1200.0,
        'category': 'คอมพิวเตอร์',
        'item_image_url': 'https://img.com/mac.jpg',
      };

      final model = FavoriteItemModel.fromJson(json, ownerName: 'John Doe');

      expect(model.id, 20);
      expect(model.title, 'MacBook Pro');
      expect(model.ownerId, 'owner_1');
      expect(model.ownerName, 'John Doe');
      expect(model.price, 1200.0);
      expect(model.imageUrl, 'https://img.com/mac.jpg');

      final entity = model.toEntity();
      expect(entity.id, 20);
      expect(entity.title, 'MacBook Pro');
      expect(entity.ownerName, 'John Doe');
    });
  });
}
