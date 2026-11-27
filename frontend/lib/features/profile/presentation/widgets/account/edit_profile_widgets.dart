import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/widgets/app_text_form_field.dart';
import '../../../../../core/theme/app_form_field_styles.dart';
import '../../../../../core/theme/app_text_styles.dart';

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class EditProfileSectionTitle extends StatelessWidget {
  final String title;
  const EditProfileSectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.primaryColor,
        letterSpacing: 0.4,
      ),
    );
  }
}

class EditProfileFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final bool readOnly;
  final String? Function(String?)? validator;

  const EditProfileFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.readOnly = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextFormField(
      controller: controller,
      label: label,
      hintText: hint,
      validator: validator,
      readOnly: readOnly,
      enabled: !readOnly,
      variant: AppFormFieldVariant.outlined,
      prefixIcon: icon,
      maxLines: maxLines,
    );
  }
}
