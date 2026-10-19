import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/chat/domain/entities/item_inquiry_data.dart';

void main() {
  group('ItemInquiryData Tests', () {
    test('isInquiry detects standard and legacy prefix formats', () {
      const msg1 = '''ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:
อุปกรณ์: Sony Alpha a7 IV

ราคา: 500 บาท / วัน''';
      expect(ItemInquiryData.isInquiry(msg1), isTrue);

      const msg2 = '''ฉันสนใจจ้างงานของคุณตามรายละเอียดนี้:
งาน: พัฒนา Mobile Application ทั้ง Android และ Ios ด้วย Flutter

ราคา: 1,500 บาท''';
      expect(ItemInquiryData.isInquiry(msg2), isTrue);

      const msg3 = 'สวัสดีครับ ยังว่างไหมครับ';
      expect(ItemInquiryData.isInquiry(msg3), isFalse);
    });

    test('toChatMessagePayload creates correct format with JSON metadata', () {
      const inquiry = ItemInquiryData(
        itemId: 12,
        itemName: 'Sony Alpha a7 IV',
        price: 500,
        unitLabel: 'วัน',
        imageUrl: 'https://example.com/sony.jpg',
      );

      final payload = inquiry.toChatMessagePayload();
      expect(payload, contains('ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:'));
      expect(payload, contains('อุปกรณ์: Sony Alpha a7 IV'));
      expect(payload, contains('ราคา: 500 บาท / วัน'));
      expect(payload, contains('[ITEM_INQUIRY:'));

      final parsed = ItemInquiryData.fromChatMessage(payload);
      expect(parsed, isNotNull);
      expect(parsed!.itemId, equals(12));
      expect(parsed.itemName, equals('Sony Alpha a7 IV'));
      expect(parsed.price, equals(500.0));
      expect(parsed.unitLabel, equals('วัน'));
      expect(parsed.imageUrl, equals('https://example.com/sony.jpg'));
    });

    test('fromChatMessage correctly parses plain text without metadata', () {
      const plainText = '''ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:
อุปกรณ์: เลนส์ Sony FE 24-70mm F2.8 GM

ราคา: 400 บาท / วัน''';

      final parsed = ItemInquiryData.fromChatMessage(
        plainText,
        imageUrl: 'https://example.com/lens.jpg',
        defaultItemId: 99,
      );

      expect(parsed, isNotNull);
      expect(parsed!.itemId, equals(99));
      expect(parsed.itemName, equals('เลนส์ Sony FE 24-70mm F2.8 GM'));
      expect(parsed.price, equals(400.0));
      expect(parsed.imageUrl, equals('https://example.com/lens.jpg'));
    });

    test(
      'fromChatMessage correctly parses user reference screenshot format',
      () {
        const userScreenshotText = '''ฉันสนใจจ้างงานของคุณตามรายละเอียดนี้:
งาน: พัฒนา Mobile Application ทั้ง Android และ Ios ด้วย Flutter

ราคา: 1,500 บาท''';

        final parsed = ItemInquiryData.fromChatMessage(
          userScreenshotText,
          imageUrl: 'https://example.com/flutter.png',
        );

        expect(parsed, isNotNull);
        expect(
          parsed!.itemName,
          equals('พัฒนา Mobile Application ทั้ง Android และ Ios ด้วย Flutter'),
        );
        expect(parsed.price, equals(1500.0));
        expect(parsed.displayPrice, contains('1,500 บาท'));
        expect(parsed.imageUrl, equals('https://example.com/flutter.png'));
      },
    );
  });
}
