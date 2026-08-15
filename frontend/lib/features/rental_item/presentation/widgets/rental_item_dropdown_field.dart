import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/widgets/app_field_label.dart';

class RentalItemDropdownField extends StatelessWidget {
  const RentalItemDropdownField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.hintText,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.validator,
  });

  final Key fieldKey;
  final String label;
  final String hintText;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppFieldLabel(text: label),
      LayoutBuilder(
        builder: (context, constraints) => FormField<String>(
          key: fieldKey,
          initialValue: value,
          validator: validator,
          builder: (field) => DropdownMenu<String>(
            width: constraints.maxWidth,
            menuHeight: 320,
            initialSelection: value,
            hintText: hintText,
            selectOnly: true,
            enableSearch: false,
            requestFocusOnTap: false,
            textStyle: const TextStyle(color: Colors.black, fontSize: 16),
            errorText: field.errorText,
            alignmentOffset: const Offset(0, 4),
            inputDecorationTheme: _inputDecorationTheme,
            menuStyle: _menuStyle,
            dropdownMenuEntries: options
                .map(
                  (option) => DropdownMenuEntry<String>(
                    value: option,
                    label: option,
                    labelWidget: Text(
                      option,
                      style: const TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  ),
                )
                .toList(growable: false),
            onSelected: (selectedValue) {
              field.didChange(selectedValue);
              onChanged(selectedValue);
            },
          ),
        ),
      ),
    ],
  );
}

final _inputDecorationTheme = InputDecorationThemeData(
  filled: true,
  fillColor: AppColors.bgFieldColor,
  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: const BorderSide(color: AppColors.bgFieldColor),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: const BorderSide(color: AppColors.bgFieldColor),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.3),
  ),
);

final _menuStyle = MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.white),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  elevation: const WidgetStatePropertyAll(4),
);
