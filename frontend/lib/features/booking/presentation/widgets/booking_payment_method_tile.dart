import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/booking_request_model.dart';

class BookingPaymentMethodSelector extends StatelessWidget {
  const BookingPaymentMethodSelector({
    super.key,
    required this.selectedMethod,
    required this.onChanged,
  });

  final BookingPaymentMethod selectedMethod;
  final ValueChanged<BookingPaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'วิธีการชำระเงิน',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 10),
        // 1. ธนาคาร
        _PaymentOptionTile(
          title: 'ธนาคาร',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFB154FF), // สีม่วงสดใสตาม UI
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          isSelected: selectedMethod == BookingPaymentMethod.bankTransfer,
          onTap: () => onChanged(BookingPaymentMethod.bankTransfer),
        ),
        const SizedBox(height: 12),
        // 2. เงินในบัญชี
        _PaymentOptionTile(
          title: 'เงินในบัญชี',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFE8EAED),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Color(0xFF1E2022),
              size: 22,
            ),
          ),
          isSelected: selectedMethod == BookingPaymentMethod.wallet,
          onTap: () => onChanged(BookingPaymentMethod.wallet),
        ),
        const SizedBox(height: 12),
        // 3. PromptPay
        _PaymentOptionTile(
          title: 'PromptPay',
          iconWidget: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFE8EAED),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: Color(0xFF1E2022),
              size: 24,
            ),
          ),
          isSelected: selectedMethod == BookingPaymentMethod.promptPay,
          onTap: () => onChanged(BookingPaymentMethod.promptPay),
        ),
      ],
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.title,
    required this.iconWidget,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final Widget iconWidget;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2022),
                  ),
                ),
              ),
              // Custom Radio Button
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryColor
                        : const Color(0xFFB5B7B9),
                    width: isSelected ? 6 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
