import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/core/constants/colors.dart';
import 'package:frontend/core/theme/app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static const pageHeaderOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primaryColor,
    scaffoldBackgroundColor: Colors.white,

    fontFamily: AppTextStyles.fontFamily,

    appBarTheme: const AppBarThemeData(
      backgroundColor: AppColors.primaryColor,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: pageHeaderOverlayStyle,
    ),

    textTheme: const TextTheme(
      headlineLarge: AppTextStyles.headingLarge,
      headlineMedium: AppTextStyles.headingMedium,
      bodyLarge: AppTextStyles.bodyLarge,
      bodySmall: AppTextStyles.bodySmall,
    ),
  );
}
