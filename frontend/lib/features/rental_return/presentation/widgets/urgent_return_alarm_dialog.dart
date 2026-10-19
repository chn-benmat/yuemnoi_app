import 'package:flutter/material.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/rental_return_session.dart';

class UrgentReturnAlarmDialog extends StatefulWidget {
  final RentalReturnSession session;
  final VoidCallback onProceedToVerification;

  const UrgentReturnAlarmDialog({
    super.key,
    required this.session,
    required this.onProceedToVerification,
  });

  static Future<void> show({
    required BuildContext context,
    required RentalReturnSession session,
    required VoidCallback onProceedToVerification,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UrgentReturnAlarmDialog(
        session: session,
        onProceedToVerification: () {
          Navigator.of(ctx).pop();
          onProceedToVerification();
        },
      ),
    );
  }

  @override
  State<UrgentReturnAlarmDialog> createState() =>
      _UrgentReturnAlarmDialogState();
}

class _UrgentReturnAlarmDialogState extends State<UrgentReturnAlarmDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 16,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ไอคอนกระดิ่งเตือนภัยเคลื่อนไหว
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.alarm_on_rounded,
                      color: Color(0xFFD97706),
                      size: 46,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // หัวข้อ
              const Text(
                'ใกล้ถึงเวลาคืนอุปกรณ์แล้ว!',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2022),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              // รายละเอียดกำหนดเวลา
              Text(
                '${widget.session.deadlineSummary}\n(เหลือเวลาอีก ${widget.session.remainingDurationText})',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD97706),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // กล่องคำแนะนำความปลอดภัย
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: Color(0xFF3B82F6),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'เพื่อความปลอดภัยของท่านและป้องกันข้อพิพาท กรุณาใช้กล้องสดถ่ายภาพสภาพอุปกรณ์ ณ ปัจจุบัน เพื่อส่งยืนยันไปยังผู้ให้เช่า',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF475569),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ปุ่มบังคับกดเพื่อถ่ายรูป
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: widget.onProceedToVerification,
                  icon: const Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    'ถ่ายรูปยืนยันสภาพเครื่องตอนนี้',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
