import 'package:flutter/material.dart';

import 'rental_item_dropdown_field.dart';

class RentalCategoryDropdownField extends StatelessWidget {
  const RentalCategoryDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const options = [
    'กล้องและอุปกรณ์ถ่ายภาพ',
    'เครื่องเสียงและอุปกรณ์จัดงาน',
    'คอมพิวเตอร์และอุปกรณ์ไอที',
    'โทรศัพท์และอุปกรณ์สื่อสาร',
    'เครื่องมือช่างและงานก่อสร้าง',
    'เครื่องใช้ไฟฟ้าและอุปกรณ์ภายในบ้าน',
    'แคมป์ปิงและกิจกรรมกลางแจ้ง',
    'กีฬาและออกกำลังกาย',
    'เกมและความบันเทิง',
    'ดนตรีและเครื่องดนตรี',
    'อื่น ๆ',
  ];

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => RentalItemDropdownField(
    fieldKey: const Key('rental-item-category'),
    label: 'หมวดหมู่',
    hintText: 'เลือกหมวดหมู่',
    options: options,
    value: value,
    onChanged: onChanged,
    validator: (value) => value == null ? 'กรุณาเลือกหมวดหมู่' : null,
  );
}
