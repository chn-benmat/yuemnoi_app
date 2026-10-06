import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

// สีและระยะของผู้ช่วย AI ใช้ร่วมกันเฉพาะ feature นี้
abstract final class ChatbotDesign {
  static const primary = AppColors.primaryColor;
  static const canvas = Color(0xFFFAF8FC);
  static const surface = Colors.white;
  static const tint = Color(0xFFF3EAFB);
  static const border = Color(0xFFE7DFF0);
  static const ink = Color(0xFF241F2D);
  static const muted = Color(0xFF6E647A);
  static const maxWidth = 560.0;
  static const body = TextStyle(
    fontFamily: 'Prompt',
    fontSize: 16,
    height: 1.55,
    color: ink,
  );
  static const button = Size(48, 48);
}
