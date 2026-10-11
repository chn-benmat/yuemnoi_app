import 'package:flutter/material.dart';

import '../constants/colors.dart';

enum AppFormFieldVariant { filled, outlined }

abstract final class AppFormFieldStyles {
  static const outlinedBorderColor = Color(0xFFD8D0E2);
  static const outlinedTextColor = Color(0xFF3C3348);
  static const outlinedHintColor = Color(0xFF746C80);
  static const outlinedDisabledColor = Color(0xFFF2F0F5);
  static const outlinedHoverColor = Color(0xFFFAF7FD);
  static const labelTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: outlinedTextColor,
  );
  static const textStyle = TextStyle(
    fontSize: 16,
    height: 1.5,
    color: outlinedTextColor,
  );

  static InputDecoration decoration(
    BuildContext context, {
    AppFormFieldVariant variant = AppFormFieldVariant.filled,
    bool enabled = true,
  }) {
    final outlined = variant == AppFormFieldVariant.outlined;
    final radius = BorderRadius.circular(outlined ? 16 : 30);
    final error = outlined
        ? Theme.of(context).colorScheme.error
        : Colors.redAccent;
    final normalBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: outlined
          ? const BorderSide(color: outlinedBorderColor)
          : BorderSide.none,
    );
    return InputDecoration(
      filled: true,
      fillColor: outlined
          ? enabled
                ? Colors.white
                : outlinedDisabledColor
          : AppColors.bgFieldColor,
      hoverColor: outlined ? outlinedHoverColor : null,
      hintStyle: TextStyle(
        color: outlined ? outlinedHintColor : AppColors.hintTextColor,
        fontSize: outlined ? 15 : 16,
      ),
      labelStyle: outlined ? labelTextStyle : null,
      floatingLabelStyle: outlined
          ? labelTextStyle.copyWith(color: AppColors.primaryColor)
          : null,
      suffixIconColor: outlined ? outlinedHintColor : null,
      contentPadding: EdgeInsets.symmetric(
        horizontal: outlined ? 16 : 24,
        vertical: 16,
      ),
      border: normalBorder,
      enabledBorder: normalBorder,
      disabledBorder: outlined ? normalBorder : null,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: error, width: 1.5),
      ),
      errorStyle: outlined
          ? TextStyle(fontSize: 12, height: 1.5, color: error)
          : const TextStyle(fontSize: 12),
      errorMaxLines: outlined ? 3 : null,
    );
  }
}
