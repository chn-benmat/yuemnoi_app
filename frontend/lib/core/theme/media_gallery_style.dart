import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/colors.dart';

/// ใช้พื้นกลางให้รูปเด่น และคงสีม่วงของแบรนด์เฉพาะปุ่มหลัก
abstract final class MediaGalleryStyle {
  static const background = Color(0xFFF7F5FA);
  static const surface = Colors.white;
  static const ink = Color(0xFF282331);
  static const muted = Color(0xFF756E80);
  static const border = Color(0xFFEAE5F0);
  static const accent = AppColors.primaryColor;
  static const accentSoft = Color(0xFFF0E6FB);
  static const viewerBackground = Color(0xFF17141D);
  static const viewerSurface = Color(0xFF2B2634);
  static const viewerMuted = Color(0xFFBDB5C9);

  static const lightSystemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
  static const darkSystemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: viewerBackground,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ButtonStyle get saveButtonStyle => FilledButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: surface,
    disabledBackgroundColor: accentSoft,
    disabledForegroundColor: muted,
    minimumSize: const Size.fromHeight(54),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );
}
