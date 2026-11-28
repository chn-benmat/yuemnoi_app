import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/profile/data/models/rental_booking_model.dart';
import 'package:frontend/features/profile/domain/entities/rental_booking.dart';

void main() {
  group('RentalBookingModel', () {
    test('fromSupabase parses booking and itemData correctly for renter', () {
      final booking = {
        'id': 101,
        'item_id': 202,
        'start_at': '2026-09-10T10:00:00Z',
        'end_at': '2026-09-12T10:00:00Z',
        'status': 'confirmed',
        'total_price': 1500.0,
        'pickup_location': 'BTS Siam',
        'pickup_address': 'Rama I Road, Bangkok',
        'latitude': '13.746',
        'longitude': '100.534',
      };

      final itemData = {
        'item_name': 'Sony A7 IV',
        'pickup_latitude': 14.8,
        'pickup_longitude': 101.5,
        'category': 'กล้อง',
        'item_image_url': 'https://example.com/camera.jpg',
      };

      final model = RentalBookingModel.fromSupabase(
        booking: booking,
        itemData: itemData,
        partnerName: 'Jane Doe',
        partnerPhone: '0812345678',
        isOwner: false,
      );

      expect(model.bookingId, 101);
      expect(model.itemId, 202);
      expect(model.title, 'Sony A7 IV');
      expect(model.category, 'กล้อง');
      expect(model.imageUrl, 'https://example.com/camera.jpg');
      expect(model.partnerName, 'Jane Doe');
      expect(model.partnerPhone, '0812345678');
      expect(model.partnerRole, 'เจ้าของอุปกรณ์');
      expect(model.statusCode, 'confirmed');
      expect(model.status, 'ยืนยันแล้ว / นัดรับของ');
      expect(model.totalPrice, 1500.0);
      expect(model.pickupLocation, 'BTS Siam');
      expect(model.latitude, 13.746);
      expect(model.longitude, 100.534);
      expect(model.toEntity().pickupAddress, 'Rama I Road, Bangkok');
      expect(model.isOwner, false);
      expect(model.startDate, DateTime.utc(2026, 9, 10, 10));
      expect(model.endDate, DateTime.utc(2026, 9, 12, 10));
      expect(model.duration, 'เช่า 2 วัน');
    });

    test('keeps booking times absent when only legacy dates are present', () {
      final model = RentalBookingModel.fromSupabase(
        booking: {'start_date': '2026-09-10', 'end_date': '2026-09-12'},
        isOwner: false,
      );

      expect(model.startDate, isNull);
      expect(model.endDate, isNull);
    });

    test('uses a listing pin only when it matches the saved meeting point', () {
      RentalBookingModel booking(String listingLocation) =>
          RentalBookingModel.fromSupabase(
            booking: {'pickup_location': 'BTS Siam'},
            itemData: {
              'pickup_location': listingLocation,
              'pickup_latitude': '13.746',
              'pickup_longitude': '100.534',
            },
            isOwner: false,
          );

      expect(booking('BTS Siam').latitude, 13.746);
      expect(booking('A different venue').latitude, isNull);
    });

    test('fromSupabase parses booking for owner with active status', () {
      final booking = {
        'id': 102,
        'item_id': 203,
        'start_at': '2026-09-01T08:00:00Z',
        'end_at': '2026-09-01T12:00:00Z',
        'type': 'รายชั่วโมง',
        'status': 'active',
        'price': 400.0,
      };

      final itemData = {
        'item_name': 'MacBook Pro',
        'category': 'แล็ปท็อป',
        'item_image_url': '["https://example.com/mac.jpg"]',
      };

      final model = RentalBookingModel.fromSupabase(
        booking: booking,
        itemData: itemData,
        partnerName: 'John Renter',
        isOwner: true,
      );

      expect(model.bookingId, 102);
      expect(model.title, 'MacBook Pro');
      expect(model.partnerName, 'John Renter');
      expect(model.partnerRole, 'ผู้เช่า');
      expect(model.statusCode, 'active');
      expect(model.status, 'กำลังเช่า');
      expect(model.duration, 'เช่า 4 ชั่วโมง');
      expect(model.imageUrl, 'https://example.com/mac.jpg');
      expect(model.isOwner, true);
    });

    test('toEntity converts RentalBookingModel to RentalBooking entity', () {
      const model = RentalBookingModel(
        bookingId: 50,
        itemId: 60,
        title: 'Drone DJI',
        partnerName: 'Partner Test',
        partnerRole: 'ผู้เช่า',
        status: 'เสร็จสิ้น',
        statusCode: 'completed',
        totalPrice: 2000.0,
        duration: 'เช่า 3 วัน',
        isOwner: true,
      );

      final entity = model.toEntity();

      expect(entity, isA<RentalBooking>());
      expect(entity.bookingId, 50);
      expect(entity.itemId, 60);
      expect(entity.title, 'Drone DJI');
      expect(entity.partnerName, 'Partner Test');
      expect(entity.status, 'เสร็จสิ้น');
      expect(entity.statusCode, 'completed');
      expect(entity.totalPrice, 2000.0);
      expect(entity.isOwner, true);
    });
  });
}
