import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_text_styles.dart';

class WalletSummaryBottomSheet extends StatefulWidget {
  final double amount;
  final VoidCallback onConfirm;

  const WalletSummaryBottomSheet({
    super.key,
    required this.amount,
    required this.onConfirm,
  });

  static Future<void> show(
    BuildContext context, {
    required double amount,
    required VoidCallback onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          WalletSummaryBottomSheet(amount: amount, onConfirm: onConfirm),
    );
  }

  @override
  State<WalletSummaryBottomSheet> createState() =>
      _WalletSummaryBottomSheetState();
}

class _WalletSummaryBottomSheetState extends State<WalletSummaryBottomSheet> {
  bool _acceptedTerms = false;

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return NumberFormat('#,##0', 'en_US').format(amount);
    }
    return NumberFormat('#,##0.00', 'en_US').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    final formatted = _formatAmount(widget.amount);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Title & Close Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 24), // Placeholder for balance alignment
              const Expanded(
                child: Text(
                  'สรุปยอดการเติมเงิน',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black87, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 20),

          // Field 1: จำนวนที่เข้าบัญชี (Light grey)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'จำนวนที่เข้าบัญชี',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    color: Color(0xFF4B5563),
                  ),
                ),
                Text(
                  '$formatted บาท',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Field 2: ยอดเงินที่ต้องชำระ (Purple tint)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFBF80FF).withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ยอดเงินที่ต้องชำระ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A0E4E),
                  ),
                ),
                Text(
                  '$formatted บาท',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A0E4E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Terms Checkbox
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _acceptedTerms,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: const BorderSide(color: Color(0xFF9CA3AF), width: 1.5),
                  activeColor: AppColors.primaryColor,
                  onChanged: (val) {
                    setState(() {
                      _acceptedTerms = val ?? false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                      color: Color(0xFF374151),
                    ),
                    children: [
                      const TextSpan(text: 'ฉันยอมรับและตอบรับ'),
                      TextSpan(
                        text: 'เงื่อนไข',
                        style: const TextStyle(
                          color: AppColors.primaryColor,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            AppRoutes.openTermsOfService(context);
                          },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Confirm Button (ยืนยัน)
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _acceptedTerms
                  ? () {
                      Navigator.of(context).pop();
                      widget.onConfirm();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                disabledBackgroundColor: AppColors.primaryColor.withValues(
                  alpha: 0.4,
                ),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 0,
              ),
              child: const Text(
                'ยืนยัน',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
