import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/widgets/app_field_label.dart';

class RentalTypeDropdownField extends StatelessWidget {
  const RentalTypeDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AppFieldLabel(text: 'ประเภทการให้เช่า'),
      DropdownButtonFormField<String>(
        key: const Key('rental-type-field'),
        initialValue: value,
        hint: const Text('เลือกประเภทการให้เช่า'),
        items: const [
          DropdownMenuItem(value: 'รายวัน', child: Text('รายวัน')),
          DropdownMenuItem(value: 'รายชั่วโมง', child: Text('รายชั่วโมง')),
        ],
        onChanged: onChanged,
        validator: (value) =>
            value == null ? 'กรุณาเลือกประเภทการให้เช่า' : null,
        decoration: _inputDecoration(),
      ),
    ],
  );
}

InputDecoration _inputDecoration() => InputDecoration(
  filled: true,
  fillColor: AppColors.bgFieldColor,
  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: BorderSide.none,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.3),
  ),
);
