import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_text_styles.dart';

class MerchantQrDialog extends StatefulWidget {
  final String qrData;
  final String? otp;
  final DateTime? expiryTime;
  final VoidCallback onRefresh;

  const MerchantQrDialog({
    super.key,
    required this.qrData,
    this.otp,
    this.expiryTime,
    required this.onRefresh,
  });

  static Future<void> show({
    required BuildContext context,
    required String qrData,
    String? otp,
    DateTime? expiryTime,
    required VoidCallback onRefresh,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => MerchantQrDialog(
        qrData: qrData,
        otp: otp,
        expiryTime: expiryTime,
        onRefresh: onRefresh,
      ),
    );
  }

  @override
  State<MerchantQrDialog> createState() => _MerchantQrDialogState();
}

class _MerchantQrDialogState extends State<MerchantQrDialog> {
  Timer? _countdownTimer;
  int _secondsRemaining = 300; // 5 นาที

  @override
  void initState() {
    super.initState();
    if (widget.expiryTime != null) {
      final diff = widget.expiryTime!.difference(DateTime.now()).inSeconds;
      _secondsRemaining = diff > 0 ? diff : 300;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    final timeFormatted =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final isExpired = _secondsRemaining <= 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Colors.white,
      elevation: 16,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: Color(0xFF10B981), size: 26),
                    SizedBox(width: 8),
                    Text(
                      'QR Code คืนอุปกรณ์',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E2022),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // คำอธิบาย
            const Text(
              'ยื่นหน้าจอนี้ให้ลูกค้าสแกนเพื่อจบขั้นตอนการคืนของ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // ตัวแสดง QR Code
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isExpired ? Colors.red : const Color(0xFF10B981),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isExpired ? Colors.red : const Color(0xFF10B981))
                        .withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: isExpired
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 50, color: Colors.red),
                        const SizedBox(height: 8),
                        const Text(
                          'QR Code หมดอายุแล้ว',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            widget.onRefresh();
                            setState(() {
                              _secondsRemaining = 300;
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('สร้างรหัสใหม่'),
                        ),
                      ],
                    )
                  : QrImageView(
                      data: widget.qrData,
                      version: QrVersions.auto,
                      size: 200.0,
                      gapless: false,
                    ),
            ),

            const SizedBox(height: 14),

            // ตัวนับเวลาหมดอายุ 5 นาที
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(
                  isExpired ? 'หมดอายุแล้ว' : 'รหัสใช้งานได้อีก: $timeFormatted นาที',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isExpired ? Colors.red : const Color(0xFF047857),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // รหัสสำรอง 6 หลัก (OTP fallback)
            if (widget.otp != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'หรือให้ลูกค้ากรอกรหัสยืนยัน 6 หลัก:',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.otp!,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: 4.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
