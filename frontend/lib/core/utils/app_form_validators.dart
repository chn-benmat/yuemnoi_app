import 'package:flutter/widgets.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import 'phone_formatter.dart';

abstract final class AppFormValidators {
  static FormFieldValidator<String> required(String message) =>
      FormBuilderValidators.required(errorText: message);

  static FormFieldValidator<String> email() => FormBuilderValidators.compose([
    required('กรุณากรอกอีเมล'),
    FormBuilderValidators.email(errorText: 'รูปแบบอีเมลไม่ถูกต้อง'),
  ]);

  static FormFieldValidator<String> password({
    String requiredMessage = 'กรุณากรอกรหัสผ่าน',
    String lengthMessage = 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร',
  }) => FormBuilderValidators.compose([
    required(requiredMessage),
    FormBuilderValidators.minLength(6, errorText: lengthMessage),
  ]);

  static FormFieldValidator<String> confirmation(
    String Function() currentPassword, {
    String requiredMessage = 'กรุณากรอกยืนยันรหัสผ่าน',
  }) => FormBuilderValidators.compose([
    required(requiredMessage),
    // อ่านค่าปัจจุบันตอนตรวจ เพื่อรองรับการแก้รหัสผ่านหลังกรอกช่องยืนยันแล้ว
    (value) => FormBuilderValidators.equal(
      currentPassword(),
      errorText: 'รหัสผ่านไม่ตรงกัน',
    )(value),
  ]);

  static FormFieldValidator<String> thaiPhone({bool localInputOnly = false}) =>
      FormBuilderValidators.compose([
        required('กรุณากรอกเบอร์โทรศัพท์'),
        if (localInputOnly) ...[
          FormBuilderValidators.equalLength(
            10,
            errorText: 'เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วย 0',
          ),
          FormBuilderValidators.startsWith(
            '0',
            errorText: 'เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วย 0',
          ),
        ],
        (value) => PhoneFormatter.isValidPhone(value)
            ? null
            : 'เบอร์โทรศัพท์ไม่ถูกต้อง (เช่น 0812345678)',
      ]);
}
