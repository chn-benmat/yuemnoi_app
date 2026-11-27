import 'package:flutter/material.dart';
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

  test('customer request retains its role while realtime replaces status', () {
    final payload =
        '${BookingRequestData.bookingPayloadPrefix}\n'
        '${BookingRequestData.customerRequestMetaTag}'
        '{"itemId":7,"bookingId":36,"status":"pending","paymentMethod":"promptpay",'
        '"startDate":"2030-01-03","startHour":9,"startMinute":15}]';
    final booking = BookingRequestData.fromChatMessage(payload)!;
    final live = BookingRequestData.fromChatMessage(
      booking.copyWith(status: 'confirmed').toChatMessagePayload(),
    )!;
    expect(live.isCustomerRequest, isTrue);
    expect(live.paymentMethod, 'promptpay');
    expect(live.status, 'confirmed');
    expect(live.requestStartAt, DateTime.utc(2030, 1, 3, 2, 15));
    expect(
      BookingRequestData.fromChatMessage('regular chat\n$payload'),
      isNull,
    );
  });

  for (final type in BookingRentalType.values) {
    test('chat offer uses the correct end date for ${type.name}', () {
      final pickupDay = DateTime(2026, 11, 24);
      final nextDay = DateTime(2026, 11, 25);
      final offer = BookingRequestData(
        item: BookingItemInfo.defaultMockItem,
        rentalType: type,
        startDate: pickupDay,
        endDate: nextDay,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        location: 'ซีคอน บางแค',
      );
      final expectedEndDate = type == BookingRentalType.hourly
          ? pickupDay
          : nextDay;

      expect(
        offer.toChatMessagePayload(),
        contains('"endDate":"${expectedEndDate.toIso8601String()}"'),
      );
    });
  }

  test('offer retains selected coordinates and uses actual message id', () {
    final data = BookingRequestData(
      item: BookingItemInfo.defaultMockItem,
      startDate: DateTime(2026, 11, 19),
      endDate: DateTime(2026, 11, 20),
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 10, minute: 0),
      location: 'จุดนัดพบ',
      latitude: 13.8,
      longitude: 100.5,
      originalMessageId: 'old',
    );
    final restored = BookingRequestData.fromChatMessage(
      data.toChatMessagePayload(),
      messageId: 'actual',
    )!;
    expect(restored.latitude, 13.8);
    expect(restored.longitude, 100.5);
    expect(restored.originalMessageId, 'actual');
  });
}
