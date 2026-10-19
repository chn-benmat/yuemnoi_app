import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class BookingPaymentMethodCard extends StatelessWidget {
  const BookingPaymentMethodCard({
    super.key,
    required this.selectedMethod,
    this.onMethodChanged,
    this.isEditable = true,
  });

  /// 'cash' หรือ 'promptpay'
  final String selectedMethod;
  final ValueChanged<String>? onMethodChanged;
  final bool isEditable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'วิธีชำระเงิน',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ตัวเลือกที่ 1: เงินสด
              _buildPaymentOption(
                key: 'cash',
                title: 'เงินสด',
                subtitle: 'ชำระเป็นเงินสดโดยตรงเมื่อรับของ',
                icon: Icons.payments_rounded,
                iconColor: const Color(0xFF059669),
                iconBgColor: const Color(0xFFECFDF5),
                isSelected: selectedMethod == 'cash',
                onTap: isEditable && onMethodChanged != null
                    ? () => onMethodChanged!('cash')
                    : null,
              ),
              const SizedBox(height: 12),

              // ตัวเลือกที่ 2: PromptPay
              _buildPaymentOption(
                key: 'promptpay',
                title: 'PromptPay',
                subtitle: 'สแกน QR Code เพื่อโอนเงินเมื่อรับของ',
                icon: Icons.qr_code_2_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFFEFF6FF),
                isSelected: selectedMethod == 'promptpay',
                onTap: isEditable && onMethodChanged != null
                    ? () => onMethodChanged!('promptpay')
                    : null,
              ),
              const SizedBox(height: 14),

              // คำแนะนำเสริมตามตัวเลือก
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: selectedMethod == 'cash'
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectedMethod == 'cash'
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFBAE6FD),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: selectedMethod == 'cash'
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedMethod == 'cash'
                            ? 'โปรดเตรียมเงินสดให้พอดีกับยอดรวมเมื่อถึงเวลานัดรับ'
                            : 'เจ้าของจะแสดง QR Code PromptPay ให้สแกนเมื่อตรวจสอบอุปกรณ์',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: selectedMethod == 'cash'
                              ? const Color(0xFF15803D)
                              : const Color(0xFF0369A1),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentOption({
    required String key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFAF5FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryColor
                : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // ไอคอนวิธีชำระเงิน
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),

            // ข้อความ
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E2022),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ปุ่ม Radio Indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryColor
                      : const Color(0xFFCBD5E1),
                  width: isSelected ? 6.5 : 1.8,
                ),
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
