import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chatbot/data/models/chat_response_model.dart';

void main() {
  group('RecommendedItemModel.fromJson', () {
    test(
      'parses Python AI service DTO format (name, image_urls list, type)',
      () {
        final json = {
          'id': 16,
          'name': 'เครื่องดูดฝุ่นไร้สาย Dyson V12 Detect Slim',
          'category': 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
          'price': 450.0,
          'type': 'วัน',
          'status': 'available',
          'image_urls': [
            'https://example.com/dyson1.jpg',
            'https://example.com/dyson2.jpg',
          ],
          'description': 'พลังดูดทรงพลังพร้อมเลเซอร์ตรวจจับฝุ่น',
        };

        final model = RecommendedItemModel.fromJson(json);

        expect(model.id, 16);
        expect(model.name, 'เครื่องดูดฝุ่นไร้สาย Dyson V12 Detect Slim');
        expect(model.price, 450.0);
        expect(model.unit, 'วัน');
        expect(model.imageUrl, 'https://example.com/dyson1.jpg');
        expect(model.category, 'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน');
        expect(model.status, 'available');
      },
    );

    test(
      'parses Go backend format (name, item_name, image_url, price_unit)',
      () {
        final json = {
          'id': '17',
          'name': 'Xiaomi Smart Air Purifier 4 Pro',
          'item_name': 'Xiaomi Smart Air Purifier 4 Pro',
          'category': 'เครื่องใช้ไฟฟ้า',
          'price': 200,
          'price_unit': 'วัน',
          'status': 'available',
          'image_url': 'https://example.com/xiaomi.jpg',
          'description': 'กรองฝุ่น PM2.5',
        };

        final model = RecommendedItemModel.fromJson(json);

        expect(model.id, 17);
        expect(model.name, 'Xiaomi Smart Air Purifier 4 Pro');
        expect(model.price, 200.0);
        expect(model.unit, 'วัน');
        expect(model.imageUrl, 'https://example.com/xiaomi.jpg');
      },
    );

    test('handles fallback when fields are missing', () {
      final json = <String, dynamic>{'id': '99'};

      final model = RecommendedItemModel.fromJson(json);

      expect(model.id, 99);
      expect(model.name, 'อุปกรณ์แนะนำ');
      expect(model.price, null);
      expect(model.unit, 'วัน');
      expect(model.imageUrl, '');
    });
  });
}
