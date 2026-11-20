import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/theme/app_text_styles.dart';

/// หน้าจอ "ชำระเงินเสร็จสิ้น" เมื่อกระบวนการส่งมอบและยืนยันรหัส PIN / QR Code สำเร็จทั้งสองฝั่ง
class RentalPaymentSuccessScreen extends StatefulWidget {
  const RentalPaymentSuccessScreen({super.key, this.returnToChat = false});

  final bool returnToChat;

  @override
  State<RentalPaymentSuccessScreen> createState() =>
      _RentalPaymentSuccessScreenState();
}

class _RentalPaymentSuccessScreenState
    extends State<RentalPaymentSuccessScreen> {
  Timer? _redirectTimer;

  @override
  void initState() {
    super.initState();
    if (widget.returnToChat) {
      _redirectTimer = Timer(const Duration(seconds: 2), _leave);
    }
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  void _leave() {
    if (!mounted) return;
    _redirectTimer?.cancel();
    if (widget.returnToChat) {
      AppRoutes.goToChatAfterHandover(context);
    } else {
      AppRoutes.goToHome(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // ── Purple Scalloped Rosette Badge with Checkmark ──
                Center(
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(140, 140),
                          painter: _ScallopedBadgePainter(
                            color: AppColors.primaryColor,
                            points: 12,
                          ),
                        ),
                        const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 72,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // ── Title & Subtitle ──
                Text(
                  widget.returnToChat
                      ? 'เริ่มเช่าอุปกรณ์สำเร็จ'
                      : 'ชำระเงินเสร็จสิ้น',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.returnToChat
                      ? 'ยืนยันการรับมอบอุปกรณ์เรียบร้อยแล้ว'
                      : 'ยินดีด้วยคุณชำระเงินเสร็จสิ้นสำเร็จ!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF4B5563),
                  ),
                ),

                const Spacer(flex: 3),

                // ── กลับสู่หน้าหลัก Button ──
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _leave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: AppColors.primaryColor.withValues(
                        alpha: 0.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: Text(
                      widget.returnToChat
                          ? 'กลับสู่หน้าแชท'
                          : 'กลับสู่หน้าหลัก',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter สำหรับ Scalloped Rosette Badge 12 แฉก
class _ScallopedBadgePainter extends CustomPainter {
  final Color color;
  final int points;

  _ScallopedBadgePainter({required this.color, this.points = 12});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.84;
    final step = math.pi / points;

    final path = Path();

    for (int i = 0; i < points * 2; i++) {
      final r = (i % 2 == 0) ? outerRadius : innerRadius;
      final angle = i * step - math.pi / 2;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevAngle = (i - 1) * step - math.pi / 2;
        final midAngle = (angle + prevAngle) / 2;
        final midR = (outerRadius + innerRadius) / 2;
        final ctrlX = center.dx + midR * math.cos(midAngle);
        final ctrlY = center.dy + midR * math.sin(midAngle);

        path.quadraticBezierTo(ctrlX, ctrlY, x, y);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScallopedBadgePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.points != points;
  }
}
