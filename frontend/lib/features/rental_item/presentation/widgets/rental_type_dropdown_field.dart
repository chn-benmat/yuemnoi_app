import 'package:flutter/material.dart';

import 'rental_item_dropdown_field.dart';

class RentalTypeDropdownField extends StatelessWidget {
  const RentalTypeDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => RentalItemDropdownField(
    fieldKey: const Key('rental-type-field'),
    label: 'ประเภทการให้เช่า',
    hintText: 'เลือกประเภทการให้เช่า',
    options: const ['รายวัน', 'รายชั่วโมง'],
    value: value,
    onChanged: onChanged,
    validator: (value) => value == null ? 'กรุณาเลือกประเภทการให้เช่า' : null,
  );
}
