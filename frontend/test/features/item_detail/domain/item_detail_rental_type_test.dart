import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/item_detail/domain/entities/item_detail.dart';

void main() {
  ItemDetail detail(String rentalType) => ItemDetail(
    id: 1,
    owner: const ItemOwner(userId: 'owner', displayName: 'Owner', imageUrl: ''),
    name: 'Tripod',
    imageUrls: const [],
    description: 'Test',
    category: 'กล้อง',
    price: 50,
    additionalDailyPrice: 300,
    status: 'available',
    rentalType: rentalType,
    reviews: const [],
    isOwner: true,
  );

  // หน้าพรีวิวตอนเพิ่ม/แก้ไขอุปกรณ์ส่งค่ามาตรฐาน hourly มาตรงจากฟอร์ม
  for (final type in ['hourly', 'รายชั่วโมง']) {
    test('$type listing shows hourly and daily prices', () {
      final item = detail(type);

      expect(item.unitLabel, 'ชั่วโมง');
      expect(item.hourlyPrice, 50);
      expect(item.dailyPrice, 300);
    });
  }

  test('daily listing shows only the daily price', () {
    final item = detail('daily');

    expect(item.unitLabel, 'วัน');
    expect(item.hourlyPrice, isNull);
    expect(item.dailyPrice, 50);
  });
}
