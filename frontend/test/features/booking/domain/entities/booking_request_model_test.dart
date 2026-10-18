import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/booking/domain/entities/booking_request_model.dart';

void main() {
  test('booking item keeps camel case payload and default rental rates', () {
    final item = BookingItemInfo.fromJson({});
    expect(item.toJson(), {
      'id': 1,
      'title': 'อุปกรณ์เช่า',
      'imageUrl': '',
      'rating': 0.0,
      'reviewCount': 0,
      'hourlyRate': 100.0,
      'dailyRate': 500.0,
      'defaultLocation': 'นัดรับตามตกลง',
      'ownerName': 'ผู้ปล่อยเช่า',
      'latitude': null,
      'longitude': null,
    });
    final parsed = BookingItemInfo.fromJson(
      BookingItemInfo.defaultMockItem.toJson(),
    );
    expect(parsed.toJson(), BookingItemInfo.defaultMockItem.toJson());
  });

  test('booking chat parsing retains item id and image override', () {
    final booking = BookingRequestData.fromChatMessage(
      '${BookingRequestData.metaStartTag}{"itemId":7,"imageUrl":"payload"}${BookingRequestData.metaEndTag}',
      imageUrl: 'override',
      messageId: 'message',
    )!;
    expect(booking.item.id, 7);
    expect(booking.item.imageUrl, 'override');
    expect(booking.item.hourlyRate, 100.0);
    expect(booking.originalMessageId, 'message');
  });
}
