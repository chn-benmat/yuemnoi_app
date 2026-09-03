import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppOrientationService {
  AppOrientationService._();
  static final AppOrientationService instance = AppOrientationService._();

  /// จุดตัดขนาดหน้าจอสำหรับแท็บเล็ต/iPad (shortestSide >= 600 dp)
  static const double tabletBreakpoint = 600.0;

  /// ตรวจสอบว่าเป็นแท็บเล็ตหรือ iPad จาก Size (dp)
  static bool isTabletFromSize(Size size) {
    return size.shortestSide >= tabletBreakpoint;
  }

  /// ตรวจสอบว่าเป็นแท็บเล็ตหรือ iPad จาก BuildContext
  static bool isTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).shortestSide >= tabletBreakpoint;
  }

  /// กำหนดทิศทางการแสดงผลหน้าจอ:
  /// - โทรศัพท์มือถือ (< 600dp): บังคับเฉพาะแนวตั้งเท่านั้น (Portrait Up)
  /// - แท็บเล็ต / iPad (>= 600dp): อนุญาตทั้งแนวตั้งและแนวนอน (Portrait & Landscape)
  static Future<void> setupOrientation() async {
    if (kIsWeb) return;
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
      if (view != null) {
        final physicalSize = view.physicalSize;
        final pixelRatio = view.devicePixelRatio;
        if (pixelRatio > 0) {
          final logicalSize = physicalSize / pixelRatio;
          final tablet = isTabletFromSize(logicalSize);
          await applyOrientation(isTablet: tablet);
          return;
        }
      }
    } catch (_) {}

    // Fallback สำหรับกรณีที่ยังคำนวณขนาดจอไม่ได้
    await applyOrientation(isTablet: false);
  }

  static Future<void> applyOrientation({required bool isTablet}) async {
    try {
      if (isTablet) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    } catch (_) {}
  }
}
