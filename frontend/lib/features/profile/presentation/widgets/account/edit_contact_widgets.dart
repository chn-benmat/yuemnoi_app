import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/widgets/app_text_form_field.dart';
import '../../../../../core/theme/app_form_field_styles.dart';

// ─── Contact Field ────────────────────────────────────────────────────────────

class EditContactField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool readOnly;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const EditContactField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.readOnly = false,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextFormField(
      controller: controller,
      label: label,
      hintText: hint,
      validator: validator,
      variant: AppFormFieldVariant.outlined,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      prefixIcon: icon,
    );
  }
}
