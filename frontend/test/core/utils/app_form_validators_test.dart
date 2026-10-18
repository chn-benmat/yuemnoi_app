import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/utils/app_form_validators.dart';

void main() {
  test('email uses a required field and standard email validation', () {
    final validate = AppFormValidators.email();
    expect(validate(''), 'กรุณากรอกอีเมล');
    expect(validate('invalid'), 'รูปแบบอีเมลไม่ถูกต้อง');
    expect(validate('user@example.technology'), isNull);
  });

  test(
    'password policy is six characters and confirmation reads latest input',
    () {
      expect(AppFormValidators.password()('12345'), isNotNull);
      expect(AppFormValidators.password()('123456'), isNull);
      var password = '123456';
      final validate = AppFormValidators.confirmation(() => password);
      expect(validate('123456'), isNull);
      password = '654321';
      expect(validate('123456'), 'รหัสผ่านไม่ตรงกัน');
      expect(validate('654321'), isNull);
    },
  );

  test('register requires local input while contact edit accepts +66', () {
    final register = AppFormValidators.thaiPhone(localInputOnly: true);
    final contact = AppFormValidators.thaiPhone();
    expect(register('0812345678'), isNull);
    expect(register('+66812345678'), isNotNull);
    expect(contact('+66812345678'), isNull);
    expect(contact('+12025550123'), isNotNull);
  });
}
