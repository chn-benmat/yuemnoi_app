import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/colors.dart';
import '../theme/app_form_field_styles.dart';
import 'app_field_label.dart';

class AppTextFormField extends StatelessWidget {
  final String label;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? prefix;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Key? fieldKey;
  final int maxLines;
  final int? minLines;
  final bool readOnly;
  final bool enabled;
  final bool enableInteractiveSelection;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final AppFormFieldVariant variant;

  const AppTextFormField({
    super.key,
    required this.label,
    this.hintText,
    this.prefixIcon,
    this.prefix,
    this.obscureText = false,
    this.suffixIcon,
    this.controller,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.fieldKey,
    this.maxLines = 1,
    this.minLines,
    this.readOnly = false,
    this.enabled = true,
    this.enableInteractiveSelection = true,
    this.onTap,
    this.onChanged,
    this.textInputAction,
    this.variant = AppFormFieldVariant.filled,
  }) : assert(prefixIcon == null || prefix == null);

  @override
  Widget build(BuildContext context) {
    final outlined = variant == AppFormFieldVariant.outlined;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(
          text: label,
          style: outlined ? AppFormFieldStyles.labelTextStyle : null,
          padding: EdgeInsets.only(left: outlined ? 0 : 4, bottom: 8),
        ),
        TextFormField(
          key: fieldKey,
          readOnly: readOnly,
          enabled: enabled,
          enableInteractiveSelection: enableInteractiveSelection,
          onTap: onTap,
          onChanged: onChanged,
          textInputAction: textInputAction,
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          minLines: minLines,
          style: outlined
              ? AppFormFieldStyles.textStyle.copyWith(
                  color: enabled
                      ? AppFormFieldStyles.outlinedTextColor
                      : AppFormFieldStyles.outlinedHintColor,
                )
              : const TextStyle(fontSize: 16, color: Colors.black87),
          decoration:
              AppFormFieldStyles.decoration(
                context,
                variant: variant,
                enabled: enabled,
              ).copyWith(
                hintText: hintText,
                prefixIcon: prefix != null
                    ? Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: outlined ? 16 : 20,
                          end: 12,
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          widthFactor: 1,
                          heightFactor: 1,
                          child: prefix,
                        ),
                      )
                    : prefixIcon != null
                    ? Icon(
                        prefixIcon,
                        color: outlined
                            ? AppFormFieldStyles.outlinedHintColor
                            : AppColors.fieldIconColor,
                        size: 22,
                      )
                    : null,
                suffixIcon: suffixIcon,
              ),
        ),
      ],
    );
  }
}
