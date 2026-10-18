import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/phone_call_service.dart';
import 'package:frontend/core/utils/phone_formatter.dart';

void main() {
  test('Thai phone formats share the local display and +66 storage value', () {
    for (final input in [
      '0812345678',
      '+66812345678',
      '66812345678',
      '+66 81-234-5678',
      '+660812345678',
    ]) {
      expect(PhoneFormatter.isValidPhone(input), isTrue, reason: input);
      expect(PhoneFormatter.formatForDisplay(input), '0812345678');
      expect(PhoneFormatter.formatForSupabase(input), '+66812345678');
      expect(normalizePhoneNumberForDialer(input), '0812345678');
    }
  });

  test('account forms retain the Thai ten-digit phone policy', () {
    for (final input in [
      null,
      '',
      '123',
      '0000000000',
      '+12025550123',
      '021234567',
    ]) {
      expect(PhoneFormatter.isValidPhone(input), isFalse, reason: '$input');
    }
    expect(PhoneFormatter.formatForDisplay(null), '');
    expect(PhoneFormatter.formatForDisplay('+6621234567'), '021234567');
    expect(PhoneFormatter.formatForSupabase('invalid'), 'invalid');
  });

  test('dialer keeps international and short numbers usable', () {
    expect(normalizePhoneNumberForDialer('+1 (202) 555-0123'), '+12025550123');
    expect(normalizePhoneNumberForDialer(' 191 '), '191');
    expect(normalizePhoneNumberForDialer(''), '');
  });
}
