import 'dart:convert';
import 'package:intl/intl.dart';

/// ข้อมูลข้อความแสดงความสนใจเช่าอุปกรณ์
class ItemInquiryData {
  const ItemInquiryData({
    this.itemId,
    required this.itemName,
    this.price,
    this.unitLabel,
    this.priceFormatted,
    this.imageUrl,
    this.rawMessage = '',
  });

  final int? itemId;
  final String itemName;
  final double? price;
  final String? unitLabel;
  final String? priceFormatted;
  final String? imageUrl;
  final String rawMessage;

  static const String inquiryPrefix = 'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:';
  static const String legacyPrefix = 'ฉันสนใจจ้างงานของคุณตามรายละเอียดนี้:';
  static const String metaStartTag = '[ITEM_INQUIRY:';
  static const String metaEndTag = ']';

  /// ตรวจสอบว่าเป็นข้อความแสดงความสนใจเช่าอุปกรณ์หรือไม่
  static bool isInquiry(String text) {
    final trimmed = text.trim();
    if (trimmed.contains(metaStartTag)) return true;
    if (trimmed.startsWith(inquiryPrefix)) return true;
    if (trimmed.startsWith(legacyPrefix)) return true;
    if (trimmed.startsWith('ฉันสนใจ') &&
        (trimmed.contains('อุปกรณ์:') || trimmed.contains('งาน:'))) {
      return true;
    }
    return false;
  }

  /// แสดงราคาที่จัดรูปแบบแล้ว
  String get displayPrice {
    if (priceFormatted != null && priceFormatted!.isNotEmpty) {
      return priceFormatted!;
    }
    if (price != null) {
      final formatter = NumberFormat('#,##0.##');
      final formatted = '${formatter.format(price)} บาท';
      if (unitLabel != null && unitLabel!.isNotEmpty) {
        return '$formatted / $unitLabel';
      }
      return formatted;
    }
    return '';
  }

  /// แปลงข้อมูลเป็น Payload สำหรับส่งเข้าแชท
  String toChatMessagePayload() {
    final priceStr = displayPrice;
    final jsonMap = <String, dynamic>{
      if (itemId != null) 'itemId': itemId,
      'itemName': itemName,
      if (price != null) 'price': price,
      if (unitLabel != null) 'unitLabel': unitLabel,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (priceFormatted != null) 'priceFormatted': priceFormatted,
    };
    final jsonString = jsonEncode(jsonMap);

    final priceLine = priceStr.isNotEmpty ? 'ราคา: $priceStr' : '';

    return '''$inquiryPrefix
อุปกรณ์: $itemName

$priceLine
$metaStartTag$jsonString$metaEndTag''';
  }

  /// แปลงข้อความแชทกลับเป็น ItemInquiryData
  static ItemInquiryData? fromChatMessage(
    String text, {
    String? imageUrl,
    int? defaultItemId,
  }) {
    if (!isInquiry(text)) return null;

    try {
      // 1. ลองอ่านจาก JSON Meta Tag หากมี
      if (text.contains(metaStartTag) && text.contains(metaEndTag)) {
        final startIdx = text.indexOf(metaStartTag) + metaStartTag.length;
        final endIdx = text.lastIndexOf(metaEndTag);
        if (startIdx < endIdx) {
          final jsonStr = text.substring(startIdx, endIdx);
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;

          final parsedItemId = (map['itemId'] as num?)?.toInt() ?? defaultItemId;
          final parsedItemName = map['itemName'] as String? ?? 'อุปกรณ์เช่า';
          final parsedPrice = (map['price'] as num?)?.toDouble();
          final parsedUnitLabel = map['unitLabel'] as String?;
          final parsedPriceFormatted = map['priceFormatted'] as String?;
          final parsedImageUrl = (imageUrl != null && imageUrl.isNotEmpty)
              ? imageUrl
              : (map['imageUrl'] as String?);

          return ItemInquiryData(
            itemId: parsedItemId,
            itemName: parsedItemName,
            price: parsedPrice,
            unitLabel: parsedUnitLabel,
            priceFormatted: parsedPriceFormatted,
            imageUrl: parsedImageUrl,
            rawMessage: text,
          );
        }
      }
    } catch (_) {}

    // 2. Fallback: แยกบรรทัดจากข้อความธรรมดา
    try {
      String cleanText = text;
      if (cleanText.contains(metaStartTag)) {
        cleanText = cleanText.substring(0, cleanText.indexOf(metaStartTag)).trim();
      }

      final lines = cleanText.split('\n');
      String parsedItemName = '';
      String parsedPriceFormatted = '';

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('อุปกรณ์:')) {
          parsedItemName = trimmed.substring('อุปกรณ์:'.length).trim();
        } else if (trimmed.startsWith('งาน:')) {
          parsedItemName = trimmed.substring('งาน:'.length).trim();
        } else if (trimmed.startsWith('ราคา:')) {
          parsedPriceFormatted = trimmed.substring('ราคา:'.length).trim();
        }
      }

      if (parsedItemName.isEmpty) {
        parsedItemName = 'อุปกรณ์เช่า';
      }

      double? parsedPrice;
      if (parsedPriceFormatted.isNotEmpty) {
        final digitsOnly = parsedPriceFormatted
            .replaceAll(',', '')
            .replaceAll('บาท', '')
            .replaceAll('฿', '')
            .split('/')
            .first
            .trim();
        parsedPrice = double.tryParse(digitsOnly);
      }

      return ItemInquiryData(
        itemId: defaultItemId,
        itemName: parsedItemName,
        price: parsedPrice,
        priceFormatted: parsedPriceFormatted.isNotEmpty ? parsedPriceFormatted : null,
        imageUrl: imageUrl,
        rawMessage: text,
      );
    } catch (_) {
      return null;
    }
  }
}
