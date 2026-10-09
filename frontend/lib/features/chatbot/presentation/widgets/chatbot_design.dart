import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

// สีและระยะของผู้ช่วย AI ใช้ร่วมกันเฉพาะ feature นี้
abstract final class ChatbotDesign {
  static const primary = AppColors.primaryColor;
  static const canvas = Colors.white;
  static const surface = Colors.white;
  static const subtle = Color(0xFFF7F7FA);
  static const tint = Color(0xFFF4ECFC);
  static const border = Color(0xFFECEAF0);
  static const ink = Color(0xFF241F2D);
  static const muted = Color(0xFF6E647A);
  static const maxWidth = 560.0;
  static const radius = 20.0;
  static const motion = Duration(milliseconds: 180);
  static const shadow = [
    BoxShadow(color: Color(0x060F0920), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static const title = TextStyle(
    fontFamily: 'Prompt',
    fontSize: 26,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: ink,
  );
  static const body = TextStyle(
    fontFamily: 'Prompt',
    fontSize: 16,
    height: 1.5,
    color: ink,
  );
  static const caption = TextStyle(
    fontFamily: 'Prompt',
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: muted,
  );
  static Duration motionFor(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : motion;
  static const button = Size(48, 48);
  static const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
}
