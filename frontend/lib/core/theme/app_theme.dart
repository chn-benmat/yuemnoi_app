import 'package:flutter/material.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/core/theme/app_text_styles.dart';

class AppTheme {
  AppTheme._();
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primaryColor,
    scaffoldBackgroundColor: Colors.white,

    fontFamily: AppTextStyles.fontFamily,

    textTheme: const TextTheme(
      headlineLarge: AppTextStyles.headingLarge,
      headlineMedium: AppTextStyles.headingMedium,
      bodyLarge: AppTextStyles.bodyLarge,
      bodySmall: AppTextStyles.bodySmall,
    ),
  );
}
