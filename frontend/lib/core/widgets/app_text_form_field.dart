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
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final AppFormFieldVariant variant;
  final bool dense;

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
    this.onFieldSubmitted,
    this.textInputAction,
    this.autofillHints,
    this.variant = AppFormFieldVariant.filled,
    this.dense = false,
  }) : assert(prefixIcon == null || prefix == null);

  @override
  Widget build(BuildContext context) {
    final outlined = variant == AppFormFieldVariant.outlined;
    final multilineIcon = maxLines > 1 && prefixIcon != null;
    final inputStyle = Theme.of(context).textTheme.titleMedium!.merge(
      outlined ? AppFormFieldStyles.textStyle : const TextStyle(fontSize: 16),
    );
    final linePainter = multilineIcon
        ? (TextPainter(
            text: TextSpan(text: 'ก', style: inputStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout())
        : null;
    final line = linePainter?.computeLineMetrics().first;
    linePainter?.dispose();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(
          text: label,
          style: dense
              ? AppFormFieldStyles.labelTextStyle.copyWith(height: 1.25)
              : outlined
              ? AppFormFieldStyles.labelTextStyle
              : null,
          padding: EdgeInsets.only(
            left: outlined ? 0 : 4,
            bottom: dense ? 2 : 8,
          ),
        ),
        Stack(
          children: [
            TextFormField(
              key: fieldKey,
              readOnly: readOnly,
              enabled: enabled,
              enableInteractiveSelection: enableInteractiveSelection,
              onTap: onTap,
              onChanged: onChanged,
              onFieldSubmitted: onFieldSubmitted,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
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
                    hintStyle: multilineIcon
                        ? inputStyle.copyWith(
                            color: outlined
                                ? AppFormFieldStyles.outlinedHintColor
                                : AppColors.hintTextColor,
                          )
                        : null,
                    contentPadding: multilineIcon
                        ? const EdgeInsetsDirectional.fromSTEB(50, 16, 16, 16)
                        : dense
                        ? EdgeInsets.symmetric(
                            horizontal: outlined ? 16 : 24,
                            vertical: 10,
                          )
                        : null,
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
                        : prefixIcon != null && maxLines == 1
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
            if (multilineIcon)
              PositionedDirectional(
                start: 16,
                top: 16 + ((line?.height ?? 24) - 22) / 2,
                child: IgnorePointer(
                  child: Icon(
                    prefixIcon,
                    size: 22,
                    color: outlined
                        ? AppFormFieldStyles.outlinedHintColor
                        : AppColors.fieldIconColor,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
