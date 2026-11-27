import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class LenderInspectionView extends StatelessWidget {
  const LenderInspectionView({
    super.key,
    required this.isChecked,
    required this.isSubmitting,
    required this.onChecked,
    required this.onConfirm,
    required this.onReport,
    required this.reportLabel,
  });

  final bool isChecked;
  final bool isSubmitting;
  final ValueChanged<bool> onChecked;
  final VoidCallback onConfirm;
  final VoidCallback onReport;
  final String reportLabel;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF0F172A);
    final checkColor = isChecked
        ? const Color(0xFFF5EDFC)
        : const Color(0xFFF8FAFC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'ตรวจรับสินค้า',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: checkColor,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isChecked
                  ? const Color(0xFFCDA7EF)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: CheckboxListTile(
            value: isChecked,
            onChanged: isSubmitting
                ? null
                : (value) => onChecked(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
            activeColor: AppColors.primaryColor,
            title: const Text(
              'ได้รับสินค้าคืนและตรวจสภาพแล้ว',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isSubmitting ? null : onReport,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(reportLabel, textAlign: TextAlign.center),
              ),
            ),
            Expanded(
              child: ElevatedButton(
                onPressed: isChecked && !isSubmitting ? onConfirm : null,
                child: Text(
                  isSubmitting ? 'กำลังยืนยัน…' : 'ยืนยันรับคืนสินค้า',
                  textAlign: TextAlign.center,
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFEDE9F2),
                  disabledForegroundColor: const Color(0xFF62596D),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
