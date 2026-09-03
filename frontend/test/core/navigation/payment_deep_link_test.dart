import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/navigation/payment_deep_link.dart';

void main() {
  test('อ่าน rental id จาก custom payment link', () {
    final result = PaymentDeepLink.parseRentalId(
      Uri.parse('yuemnoi://payments/return?rental_id=21&result=success'),
    );
    expect(result, 21);
  });

  test('อ่าน rental id จาก HTTPS fallback link', () {
    final result = PaymentDeepLink.parseRentalId(
      Uri.parse('https://api.example.com/payments/return?rental_id=21'),
    );
    expect(result, 21);
  });

  test('ไม่รับ payment link ที่ไม่มี rental id ที่ถูกต้อง', () {
    expect(
      PaymentDeepLink.parseRentalId(
        Uri.parse('yuemnoi://payments/return?rental_id=invalid'),
      ),
      isNull,
    );
  });
}
