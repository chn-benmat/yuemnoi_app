import 'package:flutter/material.dart';

import '../../../../../core/widgets/app_text_form_field.dart';
import '../../../../../core/theme/app_form_field_styles.dart';

// ─── Password Field ───────────────────────────────────────────────────────────

class ChangePasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool showPassword;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const ChangePasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.showPassword,
    required this.onToggle,
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
      obscureText: !showPassword,
      prefixIcon: Icons.lock_outline_rounded,
      suffixIcon: IconButton(
        tooltip: showPassword ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน',
        onPressed: onToggle,
        icon: Icon(
          showPassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    );
  }
}
