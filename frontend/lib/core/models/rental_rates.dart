/// ราคาต่อหน่วยของประกาศ ฐานคำนวณ hourly_rate/daily_rate จาก price/type/daily_price
/// แถวหรือข้อความเก่าที่ยังไม่มีเรตใช้ [RentalRates.legacy] ตีความแบบเดิม
class RentalRates {
  const RentalRates({this.hourly, this.daily});

  final int? hourly;
  final int? daily;

  /// เรตจากฐาน หรือ null เมื่อแถวไม่มีคีย์เรตเลย (ค่า null ของคีย์คือไม่มีเรตหน่วยนั้น)
  static RentalRates? fromKeys(
    Map<String, dynamic> row, {
    required String hourlyKey,
    required String dailyKey,
  }) {
    if (!row.containsKey(hourlyKey) && !row.containsKey(dailyKey)) return null;
    return RentalRates(
      hourly: _int(row[hourlyKey]),
      daily: _int(row[dailyKey]),
    );
  }

  /// ตีความแบบเดิม: price เป็นเรตตาม type และ daily_price เป็นเรตรายวันเสริมของประกาศรายชั่วโมง
  factory RentalRates.legacy({
    required Object? price,
    required Object? type,
    Object? dailyPrice,
  }) {
    final isHourly = isHourlyType(type);
    return RentalRates(
      hourly: isHourly ? _int(price) : null,
      daily: isHourly ? _int(dailyPrice) : _int(price),
    );
  }

  /// ตั้ง price/type ของแถวเป็นเรตหลักจากฐาน (รายชั่วโมงถ้ามี ไม่งั้นรายวัน)
  /// ให้ model ที่แสดงราคาเดียวใช้ค่าจากฐานต่อได้ แถวที่ไม่มีเรตคืนค่าเดิม
  static Map<String, dynamic> withPrimaryRate(Map<String, dynamic> row) {
    final rates = fromKeys(
      row,
      hourlyKey: 'hourly_rate',
      dailyKey: 'daily_rate',
    );
    if (rates == null || (rates.hourly == null && rates.daily == null))
      return row;
    return {
      ...row,
      'price': rates.hourly ?? rates.daily,
      'type': rates.hourly != null ? 'hourly' : 'daily',
    };
  }

  static bool isHourlyType(Object? type) =>
      switch ('$type'.trim().toLowerCase()) {
        'hourly' || 'hour' || 'รายชั่วโมง' => true,
        _ => false,
      };

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
}
